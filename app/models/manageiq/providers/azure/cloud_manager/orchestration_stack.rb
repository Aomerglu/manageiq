class ManageIQ::Providers::Azure::CloudManager::OrchestrationStack < ::OrchestrationStack
  require_dependency 'manageiq/providers/azure/cloud_manager/orchestration_stack/status'

  def self.raw_create_stack(orchestration_manager, stack_name, template, options = {})
    resource_group, create_options = make_create_options(template, options)

    orchestration_manager.with_provider_connection do |configure|
      Azure::Armrest::TemplateDeploymentService.new(configure).create(stack_name, create_options, resource_group)['id']
    end
  rescue => err
    _log.error "stack=[#{stack_name}], error: #{err.inspect}"
    raise MiqException::MiqOrchestrationProvisionError, err.to_s, err.backtrace
  end

  def self.make_create_options(template, options)
    resource_group = options[:resource_group]
    create_options = {:template => JSON.parse(template.content)}
    create_options.merge!(options).except!(:resource_group)

    if create_options[:parameters]
      create_options[:parameters] = create_options[:parameters].map { |k, v| [k, {'value' => v}] }.to_h
    end

    return resource_group, create_options
  end

  def raw_update_stack(template, options)
    resource_group, create_options = self.class.make_create_options(template, options)

    # use the same API for stack update and creation
    ext_management_system.with_provider_connection do |configure|
      Azure::Armrest::TemplateDeploymentService.new(configure).create(name, create_options, resource_group)
    end
  rescue => err
    _log.error "stack=[#{name}], error: #{err}"
    raise MiqException::MiqOrchestrationUpdateError, err.to_s, err.backtrace
  end

  def raw_delete_stack
    ext_management_system.with_provider_connection do |configure|
      Azure::Armrest::TemplateDeploymentService.new(configure).delete(name, resource_group)
    end
  rescue => err
    _log.error "stack=[#{name}], error: #{err}"
    raise MiqException::MiqOrchestrationDeleteError, err.to_s, err.backtrace
  end

  def raw_status
    ext_management_system.with_provider_connection do |configure|
      raw_stack = ::Azure::Armrest::TemplateDeploymentService.new(configure).get(name, resource_group)
      Status.new(raw_stack.fetch_path('properties', 'provisioningState'), nil)
    end
  rescue => err
    if err.to_s =~ /[D|d]eployment.+ could not be found/
      raise MiqException::MiqOrchestrationStackNotExistError, "#{name} does not exist on #{ext_management_system.name}"
    end

    _log.error "stack=[#{name}], error: #{err}"
    raise MiqException::MiqOrchestrationStatusError, err.to_s, err.backtrace
  end
end
