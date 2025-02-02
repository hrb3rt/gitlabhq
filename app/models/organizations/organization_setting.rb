# frozen_string_literal: true

module Organizations
  class OrganizationSetting < ApplicationRecord
    extend ::Organization::CurrentOrganization

    belongs_to :organization

    validates :settings, json_schema: { filename: "organization_settings" }

    jsonb_accessor :settings,
      restricted_visibility_levels: [:integer, { array: true }]

    validates_each :restricted_visibility_levels do |record, attr, value|
      value&.each do |level|
        unless Gitlab::VisibilityLevel.options.value?(level)
          record.errors.add(attr, format(_("'%{level}' is not a valid visibility level"), level: level))
        end
      end
    end

    def self.for_current_organization
      return unless current_organization

      current_organization.settings || current_organization.build_settings
    end
  end
end
