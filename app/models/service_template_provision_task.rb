class ServiceTemplateProvisionTask < MiqRequestTask
  include ReportableMixin

  validate :validate_request_type, :validate_state

  virtual_belongs_to :service_resource, :class_name => "ServiceResource"

  AUTOMATE_DRIVES = true

  def self.base_model
    ServiceTemplateProvisionTask
  end

  def provision_priority
    return 0 if service_resource.nil?
    service_resource.provision_index
  end

  def sibling_sequence_run_now?
    return true  if miq_request_task.nil? || miq_request_task.miq_request_tasks.count == 1
    return false if miq_request_task.miq_request_tasks.detect { |t| t.provision_priority < provision_priority && t.state != "finished" }
    true
  end

  def group_sequence_run_now?
    parent = miq_request_task
    return true   if parent.nil?
    return false  unless parent.group_sequence_run_now?
    return false  unless sibling_sequence_run_now?
    true
  end

  def self.get_description(req_obj)
    prov_source = req_obj.source
    svc_target_name = req_obj.get_option(:target_name)
    if svc_target_name.blank?
      svc_target_name = prov_source.respond_to?(:get_source_name) ? prov_source.get_source_name : prov_source.name
    end

    if req_obj.kind_of?(ServiceTemplateProvisionRequest)
      result = "Provisioning Service [#{svc_target_name}] from [#{prov_source.name}]"
    else
      service_resource = prov_source
      rsc_name = service_resource.name if service_resource.respond_to?(:name)
      if rsc_name.blank?
        req_template = service_resource.resource
        rsc_name = req_template.respond_to?(:get_source_name) ? req_template.get_source_name : req_template.name
      end
      if svc_target_name.blank?
        svc_tmp_id = req_obj.get_option(:src_id)
        svc_tmp = ServiceTemplate.find_by_id(svc_tmp_id)
        svc_target_name = svc_tmp.name
      end

      result = case req_template
               when ServiceTemplate
                 "Provisioning Service [#{rsc_name}] for Service [#{svc_target_name}]"
               when MiqProvisionRequestTemplate
                 "Provisioning VM [#{rsc_name}] for Service [#{svc_target_name}]"
               else
                 "Provisioning [#{rsc_name}] for Service [#{svc_target_name}]"
               end
    end

    result
  end

  def after_request_task_create
    update_attribute(:description, get_description)
    create_child_tasks
  end

  def create_child_tasks
    parent_svc = Service.find_by_id(options[:parent_service_id])
    parent_name = parent_svc.nil? ? 'none' : "#{parent_svc.class.name}:#{parent_svc.id}"
    _log.info "- creating service tasks for service <#{self.class.name}:#{id}> with parent service <#{parent_name}>"

    tasks = source.create_tasks_for_service(self, parent_svc)
    tasks.each { |t| miq_request_tasks << t }
    _log.info "- created <#{tasks.length}> service tasks for service <#{self.class.name}:#{id}> with parent service <#{parent_name}>"
  end

  def do_request
    if miq_request_tasks.size.zero?
      message = "Service does not have children processes"
      _log.info("#{message}")
      update_and_notify_parent(:state => 'provisioned', :message => message)
    else
      miq_request_tasks.each(&:deliver_to_automate)
      message = "Service Provision started"
      _log.info("#{message}")
      update_and_notify_parent(:message => message)
      queue_post_provision
    end
  end

  def queue_post_provision
    MiqQueue.put(
      :class_name   => self.class.name,
      :instance_id  => id,
      :method_name  => "do_post_provision",
      :deliver_on   => 1.minutes.from_now.utc,
      :task_id      => "#{self.class.name.underscore}_#{id}",
      :miq_callback => {:class_name => self.class.name, :instance_id => id, :method_name => :execute_callback}
    )
  end

  def do_post_provision
    update_request_status
    queue_post_provision unless state == "finished"
  end

  def deliver_to_automate(req_type = request_type, _zone = nil)
    task_check_on_execute

    _log.info("Queuing #{request_class::TASK_DESCRIPTION}: [#{description}]...")

    if self.class::AUTOMATE_DRIVES
      dialog_values = options[:dialog] || {}

      args = {
        :object_type      => self.class.name,
        :object_id        => id,
        :namespace        => "Service/Provisioning/StateMachines",
        :class_name       => "ServiceProvision_Template",
        :instance_name    => req_type,
        :automate_message => "create",
        :attrs            => dialog_values.merge!("request" => req_type)
      }

      # Automate entry point overrides from the resource_action
      ra = source.resource_actions.detect { |ra| ra.action == 'Provision' } if source.respond_to?(:resource_actions)

      unless ra.nil?
        args[:namespace]        = ra.ae_namespace unless ra.ae_namespace.blank?
        args[:class_name]       = ra.ae_class     unless ra.ae_class.blank?
        args[:instance_name]    = ra.ae_instance  unless ra.ae_instance.blank?
        args[:automate_message] = ra.ae_message   unless ra.ae_message.blank?
        args[:attrs].merge!(ra.ae_attributes)
      end
      args[:user_id] = get_user.id

      MiqQueue.put(
        :class_name  => 'MiqAeEngine',
        :method_name => 'deliver',
        :args        => [args],
        :role        => 'automate',
        :zone        => nil,
        :task_id     => "#{self.class.name.underscore}_#{id}"
      )
      update_and_notify_parent(:state => "pending", :status => "Ok",  :message => "Automation Starting")
    else
      execute_queue
    end
  end

  def service_resource
    return nil if options[:service_resource_id].blank?
    ServiceResource.find_by_id(options[:service_resource_id])
  end

  def mark_pending_items_as_finished
    miq_request.miq_request_tasks.each do |s|
      if s.state == 'pending'
        s.update_and_notify_parent(:state => "finished", :status => "Warn", :message => "Error in Request: #{miq_request.id}. Setting pending Task: #{id} to finished.")   unless id == s.id
      end
    end
  end

  def after_ae_delivery(ae_result)
    _log.info("ae_result=#{ae_result.inspect}")
    reload

    return if ae_result == 'retry'
    return if miq_request.state == 'finished'

    if ae_result == 'ok'
      update_and_notify_parent(:state => "finished", :status => "Ok", :message => display_message("#{request_class::TASK_DESCRIPTION} completed"))
    else
      mark_pending_items_as_finished
      update_and_notify_parent(:state => "finished", :status => "Error", :message => display_message("#{request_class::TASK_DESCRIPTION} failed"))
    end
  end

  def update_and_notify_parent(*args)
    prev_state = state
    super
    task_finished if state == "finished" && prev_state != "finished"
  end

  def task_finished
    service = destination
    service.raise_provisioned_event unless service.nil?
  end

  private

  def valid_states
    super + ["provisioned"]
  end
end
