# frozen_string_literal: true

require 'spec_helper'
require 'gitlab/housekeeper/runner'

# rubocop:disable RSpec/MultipleMemoizedHelpers -- there are lots of parameters at play
RSpec.describe ::Gitlab::Housekeeper::Runner do
  let(:fake_keep) { instance_double(Class) }

  let(:change1) do
    create_change(
      identifiers: %w[the identifier for the first change],
      title: "The title of MR1"
    )
  end

  let(:change2) do
    create_change(
      identifiers: %w[the identifier for the second change],
      title: "The title of MR2"
    )
  end

  let(:change3) do
    create_change(
      identifiers: %w[the identifier for the third change],
      title: "The title of MR3"
    )
  end

  before do
    fake_keep_instance = instance_double(::Gitlab::Housekeeper::Keep)
    allow(fake_keep).to receive(:new).and_return(fake_keep_instance)

    allow(fake_keep_instance).to receive(:each_change)
      .and_yield(change1)
      .and_yield(change2)
      .and_yield(change3)
  end

  describe '#run' do
    let(:git) { instance_double(::Gitlab::Housekeeper::Git) }
    let(:gitlab_client) { instance_double(::Gitlab::Housekeeper::GitlabClient) }

    before do
      stub_env('HOUSEKEEPER_FORK_PROJECT_ID', '123')
      stub_env('HOUSEKEEPER_TARGET_PROJECT_ID', '456')

      allow(::Gitlab::Housekeeper::Git).to receive(:new)
        .and_return(git)

      allow(git).to receive(:with_branch_from_branch)
        .and_yield
      allow(git).to receive(:commit_in_branch).with(change1)
        .and_return('the-identifier-for-the-first-change')
      allow(git).to receive(:commit_in_branch).with(change2)
        .and_return('the-identifier-for-the-second-change')

      allow(::Gitlab::Housekeeper::GitlabClient).to receive(:new)
        .and_return(gitlab_client)

      allow(gitlab_client).to receive(:non_housekeeper_changes)
        .and_return([])

      allow(::Gitlab::Housekeeper::Shell).to receive(:execute)
    end

    it 'loops over the keeps and creates MRs limited by max_mrs' do
      # Branches get created
      expect(git).to receive(:commit_in_branch).with(change1)
        .and_return('the-identifier-for-the-first-change')
      expect(git).to receive(:commit_in_branch).with(change2)
        .and_return('the-identifier-for-the-second-change')

      # Branches get shown and pushed
      expect(::Gitlab::Housekeeper::Shell).to receive(:execute)
        .with('git', '--no-pager', 'diff', '--color=always', 'master',
          'the-identifier-for-the-first-change', '--', 'change1.txt', 'change2.txt')
      expect(::Gitlab::Housekeeper::Shell).to receive(:execute)
        .with('git', 'push', '-f', 'housekeeper',
          'the-identifier-for-the-first-change:the-identifier-for-the-first-change')
      expect(::Gitlab::Housekeeper::Shell).to receive(:execute)
        .with('git', '--no-pager', 'diff', '--color=always', 'master',
          'the-identifier-for-the-second-change', '--', 'change1.txt', 'change2.txt')
      expect(::Gitlab::Housekeeper::Shell).to receive(:execute)
        .with('git', 'push', '-f', 'housekeeper',
          'the-identifier-for-the-second-change:the-identifier-for-the-second-change')

      # Merge requests get created
      expect(gitlab_client).to receive(:create_or_update_merge_request)
        .with(
          change: change1,
          source_project_id: '123',
          source_branch: 'the-identifier-for-the-first-change',
          target_branch: 'master',
          target_project_id: '456',
          update_title: true,
          update_description: true,
          update_labels: true,
          update_reviewers: true
        ).and_return({ 'web_url' => 'https://example.com' })
      expect(gitlab_client).to receive(:create_or_update_merge_request)
        .with(
          change: change2,
          source_project_id: '123',
          source_branch: 'the-identifier-for-the-second-change',
          target_branch: 'master',
          target_project_id: '456',
          update_title: true,
          update_description: true,
          update_labels: true,
          update_reviewers: true
        ).and_return({ 'web_url' => 'https://example.com' })

      described_class.new(max_mrs: 2, keeps: [fake_keep]).run
    end

    context 'when given filter_identifiers' do
      it 'skips a change that does not match the filter_identifiers' do
        # Branches get created. We allow branches to be created for filtered changes but we don't want to push them.
        allow(git).to receive(:commit_in_branch).and_return("the-branch-should-not-be-pushed")
        expect(git).to receive(:commit_in_branch).with(change2)
          .and_return('the-identifier-for-the-second-change')

        # Branches get shown and pushed
        expect(::Gitlab::Housekeeper::Shell).to receive(:execute)
          .with('git', '--no-pager', 'diff', '--color=always', 'master',
            'the-identifier-for-the-second-change', '--', 'change1.txt', 'change2.txt')
        expect(::Gitlab::Housekeeper::Shell).to receive(:execute)
          .with('git', 'push', '-f', 'housekeeper',
            'the-identifier-for-the-second-change:the-identifier-for-the-second-change')

        # Merge requests get created
        expect(gitlab_client).to receive(:create_or_update_merge_request)
          .with(
            change: change2,
            source_project_id: '123',
            source_branch: 'the-identifier-for-the-second-change',
            target_branch: 'master',
            target_project_id: '456',
            update_title: true,
            update_description: true,
            update_labels: true,
            update_reviewers: true
          ).and_return({ 'web_url' => 'https://example.com' })

        described_class.new(max_mrs: 2, keeps: [fake_keep], filter_identifiers: [/second/]).run
      end
    end

    context 'when title, description, code has changed already' do
      it 'does not update the changed details' do
        # First change has updated code and description so should only update title
        expect(gitlab_client).to receive(:non_housekeeper_changes)
          .with(
            source_project_id: '123',
            source_branch: 'the-identifier-for-the-first-change',
            target_branch: 'master',
            target_project_id: '456'
          ).and_return([:code, :description, :reviewers])

        # Second change has updated title and description so it should push the code
        expect(gitlab_client).to receive(:non_housekeeper_changes)
          .with(
            source_project_id: '123',
            source_branch: 'the-identifier-for-the-second-change',
            target_branch: 'master',
            target_project_id: '456'
          ).and_return([:title, :description])

        expect(::Gitlab::Housekeeper::Shell).not_to receive(:execute)
          .with('git', 'push', '-f', 'housekeeper',
            'the-identifier-for-the-first-change:the-identifier-for-the-first-change')
        expect(::Gitlab::Housekeeper::Shell).to receive(:execute)
          .with('git', 'push', '-f', 'housekeeper',
            'the-identifier-for-the-second-change:the-identifier-for-the-second-change')

        expect(gitlab_client).to receive(:create_or_update_merge_request)
          .with(
            change: change1,
            source_project_id: '123',
            source_branch: 'the-identifier-for-the-first-change',
            target_branch: 'master',
            target_project_id: '456',
            update_title: true,
            update_description: false,
            update_labels: true,
            update_reviewers: false
          ).and_return({ 'web_url' => 'https://example.com' })
        expect(gitlab_client).to receive(:create_or_update_merge_request)
          .with(
            change: change2,
            source_project_id: '123',
            source_branch: 'the-identifier-for-the-second-change',
            target_branch: 'master',
            target_project_id: '456',
            update_title: false,
            update_description: false,
            update_labels: true,
            update_reviewers: true
          ).and_return({ 'web_url' => 'https://example.com' })

        described_class.new(max_mrs: 2, keeps: [fake_keep]).run
      end
    end
  end
end
# rubocop:enable RSpec/MultipleMemoizedHelpers
