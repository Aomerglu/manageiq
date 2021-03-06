require "spec_helper"

describe VmReconfigureRequest do
  let(:admin)         { FactoryGirl.create(:user, :userid => "tester") }
  let(:ems_vmware)    { FactoryGirl.create(:ems_vmware, :zone => zone2) }
  let(:host_hardware) { FactoryGirl.build(:hardware, :logical_cpus => 40, :numvcpus => 10, :cores_per_socket => 4) }
  let(:host)          { FactoryGirl.build(:host, :hardware => host_hardware) }
  let(:request)       { FactoryGirl.create(:vm_reconfigure_request, :userid => admin.userid) }
  let(:vm_hardware)   { FactoryGirl.build(:hardware, :virtual_hw_version => "07") }
  let(:vm_redhat)     { FactoryGirl.create(:vm_redhat) }
  let(:vm_vmware)     { FactoryGirl.create(:vm_vmware, :hardware => vm_hardware, :host => host) }
  let(:zone2)         { FactoryGirl.create(:zone, :name => "zone_2") }

  before { _guid, _server, @zone1 = EvmSpecHelper.create_guid_miq_server_zone }

  it("#my_role should be 'ems_operations'") { expect(request.my_role).to eq('ems_operations') }

  context '#my_zone' do
    it "with valid source should have the VM's zone, not the requests zone" do
      vm_vmware.update_attributes(:ems_id => ems_vmware.id)
      request.update_attributes(:options => {:src_ids => [vm_vmware.id]})

      expect(request.my_zone).to     eq(vm_vmware.my_zone)
      expect(request.my_zone).not_to eq(@zone1.name)
    end

    it "with no source should be the same as the request's zone" do
      expect(request.my_zone).to eq(@zone1.name)
    end
  end

  describe "#make_request" do
    let(:alt_user) { FactoryGirl.create(:user_with_group) }
    it "creates and update a request" do
      EvmSpecHelper.local_miq_server

      expect(AuditEvent).to receive(:success).with(
        :event        => "vm_reconfigure_request_created",
        :target_class => "Vm",
        :userid       => admin.userid,
        :message      => "VM Reconfigure requested by <#{admin.userid}> for Vm:#{[vm_vmware.id].inspect}"
      )

      allow(MiqProvision).to receive(:get_next_vm_name).and_return("New VM")

      # the dialogs populate this
      values = {:src_ids => [vm_vmware.id]}

      request = described_class.make_request(nil, values, admin)

      expect(request).to                be_valid
      expect(request).to                be_a_kind_of(described_class)
      expect(request.request_type).to   eq("vm_reconfigure")
      expect(request.description).to    eq("VM Reconfigure for: #{vm_vmware.name} - ")
      expect(request.requester).to      eq(admin)
      expect(request.userid).to         eq(admin.userid)
      expect(request.requester_name).to eq(admin.name)

      # updates a request

      expect(AuditEvent).to receive(:success).with(
        :event        => "vm_reconfigure_request_updated",
        :target_class => "Vm",
        :userid       => alt_user.userid,
        :message      => "VM Reconfigure request updated by <#{alt_user.userid}> for Vm:#{[vm_vmware.id].inspect}"
      )
      described_class.make_request(request, values, alt_user)
    end
  end

  context ".request_limits" do
    subject { described_class.request_limits(@options) }

    context "RHEV only" do
      it "single vm" do
        @options = {:src_ids => [vm_redhat.id]}

        assert_rhev_cpu_and_memory_min_max
      end

      it "multiple vms" do
        @options = {:src_ids => [vm_redhat.id, FactoryGirl.create(:vm_redhat).id]}

        assert_rhev_cpu_and_memory_min_max
      end
    end

    context "Vmware only" do
      it "single vm" do
        @options = {:src_ids => [vm_vmware.id]}

        assert_vmware_cpu_and_memory_min_max
      end

      it "multiple vms" do
        hardware = FactoryGirl.build(:hardware, :virtual_hw_version => "07")
        @options = {:src_ids => [vm_vmware.id, FactoryGirl.create(:vm_vmware, :host => host, :hardware => hardware).id]}

        assert_vmware_cpu_and_memory_min_max
      end
    end

    it "hybrid" do
      @options = {:src_ids => [vm_redhat.id, vm_vmware.id]}

      assert_vmware_cpu_and_memory_min_max
    end
  end

  def assert_rhev_cpu_and_memory_min_max
    expect(subject[:min__number_of_sockets]).to eq(1)
    expect(subject[:max__number_of_sockets]).to eq(16)
    expect(subject[:min__total_vcpus]).to       eq(1)
    expect(subject[:max__total_vcpus]).to       eq(160)
    expect(subject[:min__vm_memory]).to         eq(4)
    expect(subject[:max__vm_memory]).to         eq(2.terabyte / 1.megabyte)
  end

  def assert_vmware_cpu_and_memory_min_max
    expect(subject[:min__number_of_sockets]).to eq(1)
    expect(subject[:max__number_of_sockets]).to eq(8)
    expect(subject[:min__total_vcpus]).to       eq(1)
    expect(subject[:max__total_vcpus]).to       eq(8)
    expect(subject[:min__vm_memory]).to         eq(4)
    expect(subject[:max__vm_memory]).to         eq(255.gigabyte / 1.megabyte)
  end
end
