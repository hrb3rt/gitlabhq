# frozen_string_literal: true

# Finders::Issues class
#
# Used to filter Issues collections by set of params
#
# Arguments:
#   current_user - which user use
#   params:
#     scope: 'created_by_me' or 'assigned_to_me' or 'all'
#     state: 'opened' or 'closed' or 'all'
#     group_id: integer
#     project_id: integer
#     milestone_title: string (cannot be simultaneously used with milestone_wildcard_id)
#     milestone_wildcard_id: 'none', 'any', 'upcoming', 'started' (cannot be simultaneously used with milestone_title)
#     assignee_id: integer
#     search: string
#     in: 'title', 'description', or a string joining them with comma
#     label_name: string
#     sort: string
#     my_reaction_emoji: string
#     due_date: date or '0', '', 'overdue', 'week', or 'month'
#     created_after: datetime
#     created_before: datetime
#     updated_after: datetime
#     updated_before: datetime
#     confidential: boolean
#     issue_types: array of strings (one of WorkItems::Type.base_types)
#
class IssuesFinder < IssuableFinder
  extend ::Gitlab::Utils::Override

  def self.scalar_params
    @scalar_params ||= super + [:due_date]
  end

  def klass
    Issue
  end

  def params_class
    self.class.const_get(:Params, false)
  end

  private

  def filter_items(items)
    issues = super
    issues = by_due_date(issues)
    issues = by_confidential(issues)
    by_issue_types(issues)
  end

  # Negates all params found in `negatable_params`
  def filter_negated_items(items)
    issues = super
    by_negated_issue_types(issues)
  end

  override :filter_by_full_text_search
  def filter_by_full_text_search(items)
    # This project condition is used as a hint to PG about the partitions that need searching
    # because the search data is partitioned by project.
    # In certain cases, like the recent items search, the query plan is much better without this condition.
    return super if params[:skip_full_text_search_project_condition].present?

    super.with_projects_matching_search_data
  end

  override :use_full_text_search?
  def use_full_text_search?
    return false if include_namespace_level_work_items?

    super
  end

  override :by_parent
  def by_parent(items)
    return super unless include_namespace_level_work_items?

    relations = [group_namespaces, project_namespaces].compact

    namespaces = if relations.one?
                   relations.first
                 else
                   Namespace.from_union(relations)
                 end

    items.in_namespaces(namespaces)
  end

  def group_namespaces
    return if params[:project_id] || params[:projects]

    Group.id_in(params.group).select(:id)
  end

  def project_namespaces
    params.projects.select(:project_namespace_id)
  end

  def by_confidential(items)
    Issues::ConfidentialityFilter.new(
      current_user: current_user,
      params: original_params,
      parent: params.parent,
      assignee_filter: assignee_filter
    ).filter(items)
  end

  def by_due_date(items)
    return items unless params.due_date?

    if params.filter_by_no_due_date?
      items.without_due_date
    elsif params.filter_by_any_due_date?
      items.with_due_date
    elsif params.filter_by_overdue?
      items.due_before(Date.today)
    elsif params.filter_by_due_today?
      items.due_today
    elsif params.filter_by_due_tomorrow?
      items.due_tomorrow
    elsif params.filter_by_due_this_week?
      items.due_between(Date.today.beginning_of_week, Date.today.end_of_week)
    elsif params.filter_by_due_this_month?
      items.due_between(Date.today.beginning_of_month, Date.today.end_of_month)
    elsif params.filter_by_due_next_month_and_previous_two_weeks?
      items.due_between(Date.today - 2.weeks, (Date.today + 1.month).end_of_month)
    else
      items.none
    end
  end

  def by_issue_types(items)
    issue_type_params = Array(params[:issue_types]).map(&:to_s)
    return items if issue_type_params.blank?
    return klass.none unless (WorkItems::Type.base_types.keys & issue_type_params).sort == issue_type_params.sort

    items.with_issue_type(params[:issue_types])
  end

  def by_negated_issue_types(items)
    issue_type_params = Array(not_params[:issue_types]).map(&:to_s) & WorkItems::Type.base_types.keys
    return items if issue_type_params.blank?

    items.without_issue_type(issue_type_params)
  end

  def include_namespace_level_work_items?
    params.group? && Feature.enabled?(:namespace_level_work_items, params.group)
  end
end

IssuesFinder.prepend_mod_with('IssuesFinder')
