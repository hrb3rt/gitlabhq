import FileTemplateSelector from '../file_template_selector';

export default class MetricsDashboardSelector extends FileTemplateSelector {
  constructor({ mediator }) {
    super(mediator);
    this.config = {
      key: 'metrics-dashboard-yaml',
      name: '.metrics-dashboard.yml',
      pattern: /(.metrics-dashboard.yml)/,
      type: 'metrics_dashboard_ymls',
      dropdown: '.js-metrics-dashboard-selector',
      wrapper: '.js-metrics-dashboard-selector-wrap',
    };
  }

  initDropdown() {
    this.$dropdown.glDropdown({
      data: this.$dropdown.data('data'),
      filterable: true,
      selectable: true,
      search: {
        fields: ['name'],
      },
      clicked: options => this.reportSelectionName(options),
      text: item => item.name,
    });
  }
}
