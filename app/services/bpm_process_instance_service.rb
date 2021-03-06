class BpmProcessInstanceService < ActivitiBpmService

  def self.process_instance(process_instance_id)
    hash_bpm_processes = get(
      '/runtime/process-instances/' + process_instance_id,
      basic_auth: @@auth
    )
    BpmProcessInstance.new(hash_bpm_processes)
  end

  def self.historic_process_instance(process_instance_id)
    params = query_parameters_from_hash({
        processInstanceId: process_instance_id
    })
    hash_bpm_process = get(
      "/history/historic-process-instances?#{params}",
      basic_auth: @@auth
    )['data'].first
    BpmProcessInstance.new(hash_bpm_process)
  end

  def self.process_overall_status_variable(process_instance_id)
    hash_bpm_process = get(
      "/runtime/process-instances/#{process_instance_id}/variables/process_overall_status",
      basic_auth: @@auth
    )
    hash_bpm_process
  end

  def self.process_instance_list
    process_list = get(
      '/runtime/process-instances/',
      basic_auth: @@auth
    )["data"]

    process_list.each do |p|
      processes << BpmProcessInstance.new(p)
    end

    return processes
  end

  def self.process_instance_image(process_instance)
    id = process_instance.process_instance_id.to_s
    if (process_instance.completed == true)
      get(
        '/repository/process-definitions/' + process_instance.process_definition_version.process_identifier + '/image',
        basic_auth: @@auth
      ).body

     else
      get(
        '/runtime/process-instances/' + id + '/diagram',
        basic_auth: @@auth
      ).body
    end
  end

  def self.start_process(process_id, business_key, form)
    hash_process_instance = post(
      '/runtime/process-instances',
      basic_auth: @@auth,
      body: start_process_request_body(process_id, business_key, form),
      headers: { 'Content-Type' => 'application/json' }
    )
    raise hash_process_instance["exception"] if hash_process_instance["exception"]
    BpmProcessInstance.new(hash_process_instance)
  end

  private

  def self.start_process_request_body(process_key, business_key, form)
    {
      processDefinitionId: process_key,
      businessKey: business_key,
      variables: variables_from_hash(form),
      returnVariables: true
    }.to_json
  end


end
