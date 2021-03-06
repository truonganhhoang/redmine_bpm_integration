class StartProcessJob < ActiveJob::Base
  queue_as :bpmint_start_process

  include Redmine::I18n

  def perform(issue_id)
    start_bpm_process(issue_id)
  end

  protected

  def start_bpm_process(issue_id)
    issue = Issue.find(issue_id)
    begin
      process_definition_version = issue.tracker.process_active_version
      form_data = form_values(process_definition_version.form_fields, issue)
      constants = process_constants(process_definition_version.constants)

      variables = form_data.merge(constants).merge(core_fields(issue))

      process = BpmProcessInstanceService.start_process(
        process_definition_version.process_identifier, issue.id, variables
      )
      issue.reload

      Issue.transaction do
        issue.process_instance ||= BpmIntegration::IssueProcessInstance.new
        issue.process_instance.process_instance_id = process.id
        issue.process_instance.process_definition_version = process_definition_version
        issue.process_instance.completed = process.completed
        issue.process_instance.save!(validate:false)

        if process.completed
          issue.process_instance = Setting.plugin_bpm_integration[:closed_status].to_i
        else
          issue.status_id = process.status_id_variable || Setting.plugin_bpm_integration[:doing_status].to_i
        end

        issue.save!(validate:false)

        Delayed::Worker.logger.info "#{self.class} - Issue \##{issue.id} - Processo " + issue.process_instance.process_instance_id.to_s + " iniciado com sucesso!"

        #JOB - Atualiza tarefas de um processo
        SyncBpmTasksJob.perform_now(issue.process_instance.process_instance_id)
      end
    rescue => exception
      handle_error(exception)

      self.class.reschedule_job(issue_id)
    end
  end

  def self.reschedule_job(issue_id)
    set(wait: SyncJobsPeriod.reschedule_start_process_on_error).perform_later(issue_id)
  end

  private

  def core_fields(issue)
    ActivitiBpmService.default_fields_form_values(issue)
  end

  def process_constants(constants)
    return {} if constants.blank?
    constants.map { |c| { c.identifier => c.value } }.reduce(&:merge)
  end

  def form_values(form_fields, issue)
    form_fields ||= []
    hash_fields = form_fields.map do |ff|
      field_value = (
        issue.custom_field_values.select do |cfv|
          ff.custom_field && (cfv.custom_field_id == ff.custom_field.id)
        end
      ).first.try(&:value)
      if field_value
        field_value = field_value.gsub('=>',':') if (ff.custom_field.field_format == "grid")
      end
      { ff.field_id => field_value }
    end
    hash_fields.reduce(&:merge) || {}
  end

  def handle_error(e)
    Delayed::Worker.logger.error l('error_process_start')
    Delayed::Worker.logger.error e.message
    e.backtrace.each { |line| Delayed::Worker.logger.error line }
    Delayed::Worker.logger.error "\n\n"
  end

end
