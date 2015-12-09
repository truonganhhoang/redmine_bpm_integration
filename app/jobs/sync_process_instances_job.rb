class SyncProcessInstancesJob < ActiveJob::Base
  queue_as :bpm_process_instances

  include Redmine::I18n

  def perform(issue_process_instance = nil)
    if issue_process_instance.nil?
      sync_process_instance_list
    else
      sync_process_instance(issue_process_instance)
    end
  end

  protected

  def sync_process_instance_list
    Delayed::Worker.logger.info "#{self.class} - Sincronizando process_instances"
    BpmIntegration::IssueProcessInstance.where(completed:false).each do |p|
      begin
        sync_process_instance(p)
      rescue => exception
        handle_error(p.issue, exception.message, exception)
      end
    end
    Delayed::Worker.logger.info "#{self.class} - Sincronização de process_instances concluída"
  rescue => exception
    Delayed::Worker.logger.error l('error_process_instance_job')
    Delayed::Worker.logger.error e.message
    exception.backtrace.each { |line| Delayed::Worker.logger.error line }
  end

  after_perform do |job|
    if job.arguments.empty?
      #JOB - Reagendamento
      self.class.set(wait: SyncJobsPeriod.process_instance_period).perform_later
      Delayed::Worker.logger.info "#{self.class} - Sincronização de instancias de processos agendada"
    end
  end

  def sync_process_instance(issue_process_instance)
    #TODO: Tratar erros no Activiti e atualizar para status Erro
    historic_process = BpmProcessInstanceService.historic_process_instance(issue_process_instance.process_instance_id)
    resolve_issue_process(issue_process_instance,historic_process) unless historic_process.blank? || historic_process.endTime.blank?
  end

  def resolve_issue_process(issue_process_instance, historic_process)
    issue = Issue.find(issue_process_instance.issue_id)
    update_status(issue_process_instance, historic_process, issue)

    #Seta msg de erro
    if historic_process.deleteReason
      user = User.find(Setting.plugin_bpm_integration[:bpm_user])
      Journal.new(:journalized => issue, :user => user, :notes => historic_process.deleteReason, :private_notes => true).save
    end
    issue_process_instance.completed = true
    issue_process_instance.save
    #TODO: Melhora log abaixo
    Delayed::Worker.logger.info "#{self.class} - Issue \##{issue.id.to_s} concluída mediante o fim do processo"
  end

  def update_status(issue_process_instance, historic_process, issue)
    end_events = issue_process_instance.process_definition.end_events
    end_event_id = historic_process.endActivityId

    if !end_events.blank?
      end_events.each do |end_event|
        if end_event.identifier == end_event_id
          issue.status_id = end_event.issue_status_id
          issue.save!(validate:false)
          return nil
        end
      end
    end

    issue.status_id = Setting.plugin_bpm_integration[:closed_status].to_i
    issue.save!(validate:false)
  end

  def handle_error(issue, msg, e = nil)
    Delayed::Worker.logger.error l('error_process_instance_job')
    Delayed::Worker.logger.error msg
    e.backtrace.each { |line| Delayed::Worker.logger.error line }
    user = User.find(Setting.plugin_bpm_integration[:bpm_user])
    Journal.new(:journalized => issue, :user => user, :notes => l('error_process_instance_job') + ":  #{msg}", :private_notes => true).save
  end
end
