import { shallowMount } from '@vue/test-utils';
import Vue, { nextTick } from 'vue';
import VueApollo from 'vue-apollo';
import createMockApollo from 'helpers/mock_apollo_helper';
import waitForPromises from 'helpers/wait_for_promises';

import BoardTopBar from '~/boards/components/board_top_bar.vue';
import BoardAddNewColumnTrigger from '~/boards/components/board_add_new_column_trigger.vue';
import BoardsSelector from '~/boards/components/boards_selector.vue';
import ConfigToggle from '~/boards/components/config_toggle.vue';
import IssueBoardFilteredSearch from '~/boards/components/issue_board_filtered_search.vue';
import NewBoardButton from '~/boards/components/new_board_button.vue';
import ToggleFocus from '~/boards/components/toggle_focus.vue';
import * as cacheUpdates from '~/boards/graphql/cache_updates';
import { WORKSPACE_GROUP, WORKSPACE_PROJECT } from '~/issues/constants';

import groupBoardQuery from '~/boards/graphql/group_board.query.graphql';
import projectBoardQuery from '~/boards/graphql/project_board.query.graphql';
import { mockProjectBoardResponse, mockGroupBoardResponse } from '../mock_data';

Vue.use(VueApollo);

describe('BoardTopBar', () => {
  let wrapper;
  let mockApollo;

  const projectBoardQueryHandlerSuccess = jest.fn().mockResolvedValue(mockProjectBoardResponse);
  const groupBoardQueryHandlerSuccess = jest.fn().mockResolvedValue(mockGroupBoardResponse);
  const errorMessage = 'Failed to fetch board';
  const boardQueryHandlerFailure = jest.fn().mockRejectedValue(new Error(errorMessage));

  const createComponent = ({
    provide = {},
    projectBoardQueryHandler = projectBoardQueryHandlerSuccess,
    groupBoardQueryHandler = groupBoardQueryHandlerSuccess,
  } = {}) => {
    mockApollo = createMockApollo([
      [projectBoardQuery, projectBoardQueryHandler],
      [groupBoardQuery, groupBoardQueryHandler],
    ]);

    wrapper = shallowMount(BoardTopBar, {
      apolloProvider: mockApollo,
      propsData: {
        boardId: 'gid://gitlab/Board/1',
        isSwimlanesOn: false,
        addColumnFormVisible: false,
      },
      provide: {
        swimlanesFeatureAvailable: false,
        canAdminList: false,
        isSignedIn: false,
        fullPath: 'gitlab-org',
        boardType: 'group',
        releasesFetchPath: '/releases',
        isIssueBoard: true,
        isEpicBoard: false,
        isGroupBoard: true,
        ...provide,
      },
      stubs: { IssueBoardFilteredSearch },
    });
  };

  beforeEach(() => {
    cacheUpdates.setError = jest.fn();
  });

  afterEach(() => {
    mockApollo = null;
  });

  describe('base template', () => {
    beforeEach(() => {
      createComponent();
    });

    it('renders BoardsSelector component', () => {
      expect(wrapper.findComponent(BoardsSelector).exists()).toBe(true);
    });

    it('renders IssueBoardFilteredSearch component', () => {
      expect(wrapper.findComponent(IssueBoardFilteredSearch).exists()).toBe(true);
    });

    it('renders NewBoardButton component', () => {
      expect(wrapper.findComponent(NewBoardButton).exists()).toBe(true);
    });

    it('renders ConfigToggle component', () => {
      expect(wrapper.findComponent(ConfigToggle).exists()).toBe(true);
    });

    it('renders ToggleFocus component', () => {
      expect(wrapper.findComponent(ToggleFocus).exists()).toBe(true);
    });

    it('does not render BoardAddNewColumnTrigger component', () => {
      expect(wrapper.findComponent(BoardAddNewColumnTrigger).exists()).toBe(false);
    });

    it('emits setFilters when setFilters is emitted by filtered search', () => {
      wrapper.findComponent(IssueBoardFilteredSearch).vm.$emit('setFilters');
      expect(wrapper.emitted('setFilters')).toHaveLength(1);
    });

    it('emits updateBoard when updateBoard is emitted by boards selector', () => {
      wrapper.findComponent(BoardsSelector).vm.$emit('updateBoard');
      expect(wrapper.emitted('updateBoard')).toHaveLength(1);
    });
  });

  describe('when user can admin list', () => {
    beforeEach(() => {
      createComponent({ provide: { canAdminList: true } });
    });

    it('renders BoardAddNewColumnTrigger component', () => {
      expect(wrapper.findComponent(BoardAddNewColumnTrigger).exists()).toBe(true);
    });
  });

  it.each`
    boardType            | queryHandler                       | notCalledHandler
    ${WORKSPACE_GROUP}   | ${groupBoardQueryHandlerSuccess}   | ${projectBoardQueryHandlerSuccess}
    ${WORKSPACE_PROJECT} | ${projectBoardQueryHandlerSuccess} | ${groupBoardQueryHandlerSuccess}
  `('fetches $boardType boards', async ({ boardType, queryHandler, notCalledHandler }) => {
    createComponent({
      provide: {
        boardType,
        isProjectBoard: boardType === WORKSPACE_PROJECT,
        isGroupBoard: boardType === WORKSPACE_GROUP,
      },
    });

    await nextTick();

    expect(queryHandler).toHaveBeenCalled();
    expect(notCalledHandler).not.toHaveBeenCalled();
  });

  it.each`
    boardType
    ${WORKSPACE_GROUP}
    ${WORKSPACE_PROJECT}
  `('sets error when $boardType board query fails', async ({ boardType }) => {
    createComponent({
      provide: {
        boardType,
        isProjectBoard: boardType === WORKSPACE_PROJECT,
        isGroupBoard: boardType === WORKSPACE_GROUP,
      },
      groupBoardQueryHandler: boardQueryHandlerFailure,
      projectBoardQueryHandler: boardQueryHandlerFailure,
    });

    await waitForPromises();
    expect(cacheUpdates.setError).toHaveBeenCalled();
  });
});
