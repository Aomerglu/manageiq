require "spec_helper"

describe MiqEventCatcherOpenstackInfra do
  before do
    @ems = FactoryGirl.create(:ems_openstack_infra)
    @ems.stub(:authentication_valid?).and_return(true)
    MiqEventCatcherOpenstackInfra.stub(:all_ems_in_zone).and_return([@ems])
  end

  it "logs info about EMS that do not have Event Monitors available" do
    @ems.stub(:event_monitor_available?).and_return(false)
    $log.should_receive(:info).with(/Event Monitor unavailable for #{@ems.name}/)
    MiqEventCatcherOpenstackInfra.all_valid_ems_in_zone.should_not include @ems
  end

  it "does not log info about unavailable Event Monitors when EMS can provide an event monitor" do
    @ems.stub(:event_monitor_available?).and_return(true)
    $log.should_not_receive(:info).with(/Event Monitor unavailable for #{@ems.name}/)
    MiqEventCatcherOpenstackInfra.all_valid_ems_in_zone.should include @ems
  end
end
