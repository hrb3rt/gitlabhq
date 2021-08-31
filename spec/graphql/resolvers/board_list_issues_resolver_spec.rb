# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Resolvers::BoardListIssuesResolver do
  include GraphqlHelpers

  let_it_be(:user)          { create(:user) }
  let_it_be(:unauth_user)   { create(:user) }
  let_it_be(:user_project)  { create(:project, creator_id: user.id, namespace: user.namespace ) }
  let_it_be(:group)         { create(:group, :private) }

  shared_examples_for 'group and project board list issues resolver' do
    before do
      board_parent.add_developer(user)
    end

    # auth is handled by the parent object
    context 'when authorized' do
      let!(:issue1) { create(:issue, project: project, labels: [label], relative_position: 10) }
      let!(:issue2) { create(:issue, project: project, labels: [label, label2], relative_position: 12) }
      let!(:issue3) { create(:issue, project: project, labels: [label, label3], relative_position: 10) }
      let!(:issue4) { create(:issue, project: project, labels: [label], relative_position: nil) }

      it 'returns issues in the correct order with non-nil relative positions', :aggregate_failures do
        # by relative_position and then ID
        result = resolve_board_list_issues

        expect(result.map(&:id)).to eq [issue3.id, issue1.id, issue2.id, issue4.id]
        expect(result.map(&:relative_position)).not_to include(nil)
      end

      it 'finds only issues matching filters' do
        result = resolve_board_list_issues(args: { filters: { label_name: [label.title], not: { label_name: [label2.title] } } })

        expect(result).to match_array([issue1, issue3, issue4])
      end

      it 'finds only issues matching search param' do
        result = resolve_board_list_issues(args: { filters: { search: issue1.title } })

        expect(result).to match_array([issue1])
      end

      it 'raises an exception if both assignee_username and assignee_wildcard_id are present' do
        expect do
          resolve_board_list_issues(args: { filters: { assignee_username: ['username'], assignee_wildcard_id: 'NONE' } })
        end.to raise_error(Gitlab::Graphql::Errors::ArgumentError)
      end

      it 'accepts assignee wildcard id NONE' do
        result = resolve_board_list_issues(args: { filters: { assignee_wildcard_id: 'NONE' } })

        expect(result).to match_array([issue1, issue2, issue3, issue4])
      end

      it 'accepts assignee wildcard id ANY' do
        result = resolve_board_list_issues(args: { filters: { assignee_wildcard_id: 'ANY' } })

        expect(result).to match_array([])
      end
    end
  end

  describe '#resolve' do
    context 'when project boards' do
      let_it_be(:label) { create(:label, project: user_project) }
      let_it_be(:label2) { create(:label, project: user_project) }
      let_it_be(:label3) { create(:label, project: user_project) }
      let_it_be(:board) { create(:board, resource_parent: user_project) }
      let_it_be(:list) { create(:list, board: board, label: label) }

      let(:board_parent) { user_project }
      let(:project) { user_project }

      it_behaves_like 'group and project board list issues resolver'
    end

    context 'when group boards' do
      let_it_be(:label) { create(:group_label, group: group) }
      let_it_be(:label2) { create(:group_label, group: group) }
      let_it_be(:label3) { create(:group_label, group: group) }
      let_it_be(:board) { create(:board, resource_parent: group) }
      let_it_be(:list) { create(:list, board: board, label: label) }

      let(:board_parent) { group }
      let!(:project) { create(:project, :private, group: group) }

      it_behaves_like 'group and project board list issues resolver'
    end
  end

  def resolve_board_list_issues(args: {}, current_user: user)
    resolve(described_class, obj: list, args: args, ctx: { current_user: current_user }).items
  end
end
