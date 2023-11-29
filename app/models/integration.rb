# frozen_string_literal: true

# To add new integration you should build a class inherited from Integration
# and implement a set of methods
class Integration < ApplicationRecord
  include Sortable
  include Importable
  include Integrations::Loggable
  include Integrations::HasDataFields
  include Integrations::ResetSecretFields
  include FromUnion
  include EachBatch
  include IgnorableColumns
  extend ::Gitlab::Utils::Override

  UnknownType = Class.new(StandardError)

  self.allow_legacy_sti_class = true
  self.inheritance_column = :type_new

  INTEGRATION_NAMES = %w[
    asana assembla bamboo bugzilla buildkite campfire clickup confluence custom_issue_tracker datadog discord
    drone_ci emails_on_push ewm external_wiki hangouts_chat harbor irker jira
    mattermost mattermost_slash_commands microsoft_teams packagist pipelines_email
    pivotaltracker prometheus pumble pushover redmine slack slack_slash_commands squash_tm teamcity telegram
    unify_circuit webex_teams youtrack zentao
  ].freeze

  # See: https://gitlab.com/gitlab-org/gitlab/-/issues/345677
  PROJECT_SPECIFIC_INTEGRATION_NAMES = %w[
    apple_app_store gitlab_slack_application google_play jenkins
  ].freeze

  # Fake integrations to help with local development.
  DEV_INTEGRATION_NAMES = %w[
    mock_ci mock_monitoring
  ].freeze

  # Base classes which aren't actual integrations.
  BASE_CLASSES = %w[
    Integrations::BaseChatNotification
    Integrations::BaseCi
    Integrations::BaseIssueTracker
    Integrations::BaseMonitoring
    Integrations::BaseSlackNotification
    Integrations::BaseSlashCommands
    Integrations::BaseThirdPartyWiki
  ].freeze

  BASE_ATTRIBUTES = %w[id instance project_id group_id created_at updated_at
    encrypted_properties encrypted_properties_iv properties].freeze

  SECTION_TYPE_CONFIGURATION = 'configuration'
  SECTION_TYPE_CONNECTION = 'connection'
  SECTION_TYPE_TRIGGER = 'trigger'

  SNOWPLOW_EVENT_ACTION = 'perform_integrations_action'
  SNOWPLOW_EVENT_LABEL = 'redis_hll_counters.ecosystem.ecosystem_total_unique_counts_monthly'

  attr_encrypted :properties,
    mode: :per_attribute_iv,
    key: Settings.attr_encrypted_db_key_base_32,
    algorithm: 'aes-256-gcm',
    marshal: true,
    marshaler: ::Gitlab::Json,
    encode: false,
    encode_iv: false

  alias_attribute :name, :title
  # Handle assignment of props with symbol keys.
  # To do this correctly, we need to call the method generated by attr_encrypted.
  alias_method :attr_encrypted_props=, :properties=
  private :attr_encrypted_props=

  def properties=(props)
    self.attr_encrypted_props = props&.with_indifferent_access&.freeze
  end

  alias_attribute :type, :type_new

  attribute :active, default: false
  attribute :alert_events, default: true
  attribute :incident_events, default: false
  attribute :category, default: 'common'
  attribute :commit_events, default: true
  attribute :confidential_issues_events, default: true
  attribute :confidential_note_events, default: true
  attribute :deployment_events, default: false
  attribute :issues_events, default: true
  attribute :job_events, default: true
  attribute :merge_requests_events, default: true
  attribute :note_events, default: true
  attribute :pipeline_events, default: true
  attribute :push_events, default: true
  attribute :tag_push_events, default: true
  attribute :wiki_page_events, default: true
  attribute :group_mention_events, default: false
  attribute :group_confidential_mention_events, default: false

  after_initialize :initialize_properties

  after_commit :reset_updated_properties

  belongs_to :project, inverse_of: :integrations
  belongs_to :group, inverse_of: :integrations

  validates :project_id, presence: true, unless: -> { instance_level? || group_level? }
  validates :group_id, presence: true, unless: -> { instance_level? || project_level? }
  validates :project_id, :group_id, absence: true, if: -> { instance_level? }
  validates :type, presence: true, exclusion: BASE_CLASSES
  validates :type, uniqueness: { scope: :instance }, if: :instance_level?
  validates :type, uniqueness: { scope: :project_id }, if: :project_level?
  validates :type, uniqueness: { scope: :group_id }, if: :group_level?
  validate :validate_belongs_to_project_or_group

  scope :external_issue_trackers, -> { where(category: 'issue_tracker').active }
  scope :third_party_wikis, -> { where(category: 'third_party_wiki').active }
  scope :by_name, ->(name) { by_type(integration_name_to_type(name)) }
  scope :external_wikis, -> { by_name(:external_wiki).active }
  scope :active, -> { where(active: true) }
  scope :by_type, ->(type) { where(type: type) } # INTERNAL USE ONLY: use by_name instead
  scope :by_active_flag, ->(flag) { where(active: flag) }
  scope :inherit_from_id, ->(id) { where(inherit_from_id: id) }
  scope :with_default_settings, -> { where.not(inherit_from_id: nil) }
  scope :with_custom_settings, -> { where(inherit_from_id: nil) }
  scope :for_group, ->(group) {
                      where(group_id: group, type: available_integration_types(include_project_specific: false))
                    }
  scope :for_instance, -> { where(instance: true, type: available_integration_types(include_project_specific: false)) }

  scope :push_hooks, -> { where(push_events: true, active: true) }
  scope :tag_push_hooks, -> { where(tag_push_events: true, active: true) }
  scope :issue_hooks, -> { where(issues_events: true, active: true) }
  scope :confidential_issue_hooks, -> { where(confidential_issues_events: true, active: true) }
  scope :merge_request_hooks, -> { where(merge_requests_events: true, active: true) }
  scope :note_hooks, -> { where(note_events: true, active: true) }
  scope :confidential_note_hooks, -> { where(confidential_note_events: true, active: true) }
  scope :job_hooks, -> { where(job_events: true, active: true) }
  scope :archive_trace_hooks, -> { where(archive_trace_events: true, active: true) }
  scope :pipeline_hooks, -> { where(pipeline_events: true, active: true) }
  scope :wiki_page_hooks, -> { where(wiki_page_events: true, active: true) }
  scope :deployment_hooks, -> { where(deployment_events: true, active: true) }
  scope :alert_hooks, -> { where(alert_events: true, active: true) }
  scope :incident_hooks, -> { where(incident_events: true, active: true) }
  scope :deployment, -> { where(category: 'deployment') }
  scope :group_mention_hooks, -> { where(group_mention_events: true, active: true) }
  scope :group_confidential_mention_hooks, -> { where(group_confidential_mention_events: true, active: true) }

  class << self
    private

    attr_writer :field_storage

    def field_storage
      @field_storage || :properties
    end
  end

  # :nocov: Tested on subclasses.
  def self.field(name, storage: field_storage, **attrs)
    fields << ::Integrations::Field.new(name: name, integration_class: self, **attrs)

    case storage
    when :attribute
      # noop
    when :properties
      prop_accessor(name)
    when :data_fields
      data_field(name)
    else
      raise ArgumentError, "Unknown field storage: #{storage}"
    end

    boolean_accessor(name) if attrs[:type] == :checkbox && storage != :attribute
  end
  # :nocov:

  def self.fields
    @fields ||= []
  end

  def fields
    self.class.fields.dup
  end

  # Provide convenient accessor methods for each serialized property.
  # Also keep track of updated properties in a similar way as ActiveModel::Dirty
  def self.prop_accessor(*args)
    args.each do |arg|
      class_eval <<~RUBY, __FILE__, __LINE__ + 1
        unless method_defined?(arg)
          def #{arg}
            properties['#{arg}'] if properties.present?
          end
        end

        def #{arg}=(value)
          self.properties ||= {}
          updated_properties['#{arg}'] = #{arg} unless #{arg}_changed?
          self.properties = self.properties.merge('#{arg}' => value)
        end

        def #{arg}_changed?
          #{arg}_touched? && #{arg} != #{arg}_was
        end

        def #{arg}_touched?
          updated_properties.include?('#{arg}')
        end

        def #{arg}_was
          updated_properties['#{arg}']
        end
      RUBY
    end
  end

  # Provide convenient boolean accessor methods for each serialized property.
  # Also keep track of updated properties in a similar way as ActiveModel::Dirty
  def self.boolean_accessor(*args)
    args.each do |arg|
      class_eval <<~RUBY, __FILE__, __LINE__ + 1
        # Make the original getter available as a private method.
        alias_method :#{arg}_before_type_cast, :#{arg}
        private(:#{arg}_before_type_cast)

        def #{arg}
          Gitlab::Utils.to_boolean(#{arg}_before_type_cast)
        end

        def #{arg}?
          # '!!' is used because nil or empty string is converted to nil
          !!#{arg}
        end
      RUBY
    end
  end
  private_class_method :boolean_accessor

  def self.title
    raise NotImplementedError
  end

  def self.description
    raise NotImplementedError
  end

  def self.help
    # no-op
  end

  def self.to_param
    raise NotImplementedError
  end

  def self.event_names
    supported_events.map { |event| IntegrationsHelper.integration_event_field_name(event) }
  end

  def self.supported_events
    %w[commit push tag_push issue confidential_issue merge_request wiki_page]
  end

  def self.default_test_event
    'push'
  end

  def self.event_description(event)
    IntegrationsHelper.integration_event_description(event)
  end

  def self.find_or_initialize_non_project_specific_integration(name, instance: false, group_id: nil)
    return unless name.in?(available_integration_names(include_project_specific: false))

    integration_name_to_model(name).find_or_initialize_by(instance: instance, group_id: group_id)
  end

  def self.find_or_initialize_all_non_project_specific(scope)
    scope + build_nonexistent_integrations_for(scope)
  end

  def self.build_nonexistent_integrations_for(scope)
    nonexistent_integration_types_for(scope).map do |type|
      integration_type_to_model(type).new
    end
  end
  private_class_method :build_nonexistent_integrations_for

  # Returns a list of integration types that do not exist in the given scope.
  # Example: ["AsanaService", ...]
  def self.nonexistent_integration_types_for(scope)
    # Using #map instead of #pluck to save one query count. This is because
    # ActiveRecord loaded the object here, so we don't need to query again later.
    available_integration_types(include_project_specific: false) - scope.map(&:type)
  end
  private_class_method :nonexistent_integration_types_for

  # Returns a list of available integration names.
  # Example: ["asana", ...]
  def self.available_integration_names(include_project_specific: true, include_dev: true)
    names = integration_names
    names += project_specific_integration_names if include_project_specific
    names += dev_integration_names if include_dev

    names.sort_by(&:downcase)
  end

  def self.integration_names
    INTEGRATION_NAMES
  end

  def self.dev_integration_names
    return [] unless Gitlab.dev_or_test_env?

    DEV_INTEGRATION_NAMES
  end

  def self.project_specific_integration_names
    names = PROJECT_SPECIFIC_INTEGRATION_NAMES.dup
    names.delete('gitlab_slack_application') unless Gitlab::CurrentSettings.slack_app_enabled || Gitlab.dev_or_test_env?
    names
  end

  # Returns a list of available integration types.
  # Example: ["Integrations::Asana", ...]
  def self.available_integration_types(include_project_specific: true, include_dev: true)
    available_integration_names(include_project_specific: include_project_specific, include_dev: include_dev).map do
      integration_name_to_type(_1)
    end
  end

  # Returns the model for the given integration name.
  # Example: :asana => Integrations::Asana
  def self.integration_name_to_model(name)
    type = integration_name_to_type(name)
    integration_type_to_model(type)
  end

  # Returns the STI type for the given integration name.
  # Example: "asana" => "Integrations::Asana"
  def self.integration_name_to_type(name)
    name = name.to_s
    if available_integration_names.exclude?(name)
      Gitlab::ErrorTracking.track_and_raise_for_dev_exception(UnknownType.new(name.inspect))
    else
      "Integrations::#{name.camelize}"
    end
  end

  # Returns the model for the given STI type.
  # Example: "Integrations::Asana" => Integrations::Asana
  def self.integration_type_to_model(type)
    type.constantize
  end
  private_class_method :integration_type_to_model

  def self.build_from_integration(integration, project_id: nil, group_id: nil)
    new_integration = integration.dup

    new_integration.instance = false
    new_integration.project_id = project_id
    new_integration.group_id = group_id
    new_integration.inherit_from_id = integration.id if integration.inheritable?
    new_integration
  end

  # Duplicating an integration also duplicates the data fields. Duped records have different ciphertexts.
  override :dup
  def dup
    new_integration = super
    new_integration.assign_attributes(reencrypt_properties)

    if supports_data_fields?
      fields = data_fields.dup
      fields.integration = new_integration
    end

    new_integration
  end

  def inheritable?
    instance_level? || group_level?
  end

  def self.instance_exists_for?(type)
    exists?(instance: true, type: type)
  end

  def self.default_integration(type, scope)
    closest_group_integration(type, scope) || instance_level_integration(type)
  end

  def self.closest_group_integration(type, scope)
    group_ids = scope.ancestors(hierarchy_order: :asc).reselect(:id)
    array = group_ids.to_sql.present? ? "array(#{group_ids.to_sql})" : 'ARRAY[]'

    where(type: type, group_id: group_ids, inherit_from_id: nil)
      .order(Arel.sql("array_position(#{array}::bigint[], #{table_name}.group_id)"))
      .first
  end
  private_class_method :closest_group_integration

  def self.instance_level_integration(type)
    find_by(type: type, instance: true)
  end
  private_class_method :instance_level_integration

  # Returns the number of successfully saved integrations
  # Duplicate integrations are excluded from this count by their validations.
  def self.create_from_active_default_integrations(owner, association)
    group_ids = sorted_ancestors(owner).select(:id)
    array = group_ids.to_sql.present? ? "array(#{group_ids.to_sql})" : 'ARRAY[]'
    order = Arel.sql("type_new ASC, array_position(#{array}::bigint[], #{table_name}.group_id), instance DESC")

    from_union([active.where(instance: true), active.where(group_id: group_ids, inherit_from_id: nil)])
      .order(order)
      .group_by(&:type)
      .count { |_type, parents| build_from_integration(parents.first, association => owner.id).save }
  end

  def self.inherited_descendants_from_self_or_ancestors_from(integration)
    inherit_from_ids =
      where(type: integration.type, group: integration.group.self_and_ancestors)
        .or(where(type: integration.type, instance: true)).select(:id)

    from_union([
      where(type: integration.type, inherit_from_id: inherit_from_ids, group: integration.group.descendants),
      where(type: integration.type, inherit_from_id: inherit_from_ids,
        project: Project.in_namespace(integration.group.self_and_descendants))
    ])
  end

  def activated?
    active
  end

  def operating?
    active && persisted?
  end

  def show_active_box?
    true
  end

  def editable?
    true
  end

  def activate_disabled_reason
    nil
  end

  def category
    read_attribute(:category).to_sym
  end

  def initialize_properties
    self.properties = {} if has_attribute?(:encrypted_properties) && encrypted_properties.nil?
  end

  def title
    self.class.title
  end

  def description
    self.class.description
  end

  def help
    self.class.help
  end

  def to_param
    self.class.to_param
  end

  def sections
    []
  end

  def secret_fields
    fields.select(&:secret?).pluck(:name)
  end

  # Expose a list of fields in the JSON endpoint.
  #
  # This list is used in `Integration#as_json(only: json_fields)`.
  def json_fields
    %w[active]
  end

  # properties is always nil - ignore it.
  override :attributes
  def attributes
    super.except('properties')
  end

  # Returns a hash of attributes (columns => values) used for inserting into the database.
  def to_database_hash
    column = self.class.attribute_aliases.fetch('type', 'type')

    attributes_for_database.except(*BASE_ATTRIBUTES)
    .merge(column => type)
    .merge(reencrypt_properties)
  end

  def reencrypt_properties
    unless properties.nil? || properties.empty?
      alg = self.class.attr_encrypted_attributes[:properties][:algorithm]
      iv = generate_iv(alg)
      ep = self.class.attr_encrypt(:properties, properties, { iv: iv })
    end

    { 'encrypted_properties' => ep, 'encrypted_properties_iv' => iv }
  end

  def event_channel_names
    []
  end

  def event_names
    self.class.event_names
  end

  def api_field_names
    fields.reject { _1[:type] == :password || _1[:name] == 'webhook' || (_1.key?(:if) && _1[:if] != true) }.pluck(:name)
  end

  def form_fields
    fields.reject { _1[:api_only] == true || (_1.key?(:if) && _1[:if] != true) }
  end

  def configurable_events
    events = supported_events

    # No need to disable individual triggers when there is only one
    if events.count == 1
      []
    else
      events
    end
  end

  def supported_events
    self.class.supported_events
  end

  def default_test_event
    self.class.default_test_event
  end

  def execute(data)
    # implement inside child
  end

  def test(data)
    # default implementation
    result = execute(data)
    { success: result.present?, result: result }
  end

  # Disable test for instance-level and group-level integrations.
  # https://gitlab.com/gitlab-org/gitlab/-/issues/213138
  def testable?
    project_level?
  end

  def project_level?
    project_id.present?
  end

  def group_level?
    group_id.present?
  end

  def instance_level?
    instance?
  end

  def parent
    project || group
  end

  # Returns a hash of the properties that have been assigned a new value since last save,
  # indicating their original values (attr => original value).
  # ActiveRecord does not provide a mechanism to track changes in serialized keys,
  # so we need a specific implementation for integration properties.
  # This allows to track changes to properties set with the accessor methods,
  # but not direct manipulation of properties hash.
  def updated_properties
    @updated_properties ||= ActiveSupport::HashWithIndifferentAccess.new
  end

  def reset_updated_properties
    @updated_properties = nil
  end

  def async_execute(data)
    return if ::Gitlab::SilentMode.enabled?
    return unless supported_events.include?(data[:object_kind])

    Integrations::ExecuteWorker.perform_async(id, data.deep_stringify_keys)
  end

  # override if needed
  def supports_data_fields?
    false
  end

  def chat?
    category == :chat
  end

  def ci?
    category == :ci
  end

  private

  # Ancestors sorted by hierarchy depth in bottom-top order.
  def self.sorted_ancestors(scope)
    if scope.root_ancestor.use_traversal_ids?
      Namespace.from(scope.ancestors(hierarchy_order: :asc))
    else
      scope.ancestors
    end
  end

  def validate_belongs_to_project_or_group
    errors.add(:project_id, 'The service cannot belong to both a project and a group') if project_level? && group_level?
  end

  def validate_recipients?
    activated? && !importing?
  end
end

Integration.prepend_mod_with('Integration')
