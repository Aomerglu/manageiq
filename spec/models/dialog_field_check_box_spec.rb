require "spec_helper"

describe DialogFieldCheckBox do
  describe "#value" do
    let(:dialog_field) { described_class.new(:dynamic => dynamic, :value => value) }

    context "when the dialog field is dynamic" do
      let(:dynamic) { true }

      context "when the current value is blank" do
        let(:value) { "" }

        before do
          DynamicDialogFieldValueProcessor.stub(:values_from_automate).with(dialog_field).and_return("processor")
        end

        it "returns the values from the value processor" do
          expect(dialog_field.value).to eq("processor")
        end
      end

      context "when the current value is not blank" do
        let(:value) { "test" }

        it "returns the current value" do
          expect(dialog_field.value).to eq("test")
        end
      end
    end

    context "when the dialog field is not dynamic" do
      let(:dynamic) { false }
      let(:value) { "test" }

      it "returns the current value" do
        expect(dialog_field.value).to eq("test")
      end
    end
  end

  describe "#checked?" do
    let(:dialog_field) { described_class.new(:value => value) }

    context "when the value is 't'" do
      let(:value) { "t" }

      it "returns true" do
        expect(dialog_field.checked?).to be_true
      end
    end

    context "when the value is anything else" do
      let(:value) { "1" }

      it "returns false" do
        expect(dialog_field.checked?).to be_false
      end
    end
  end

  describe "#initial_values" do
    let(:dialog_field) { described_class.new }

    it "returns false" do
      expect(dialog_field.initial_values).to be_false
    end
  end

  describe "#script_error_values" do
    let(:dialog_field_checkbox) { described_class.new }

    it "returns the script error value" do
      expect(dialog_field_checkbox.script_error_values).to eq("<Script error>")
    end
  end

  describe "#normalize_automate_values" do
    let(:dialog_field) { described_class.new }
    let(:automate_hash) do
      {
        "value"     => value,
        "required"  => true,
        "read_only" => true
      }
    end

    shared_examples_for "DialogFieldCheckbox#normalize_automate_values" do
      before do
        dialog_field.normalize_automate_values(automate_hash)
      end

      it "sets the required" do
        expect(dialog_field.required).to be_true
      end

      it "sets the read_only" do
        expect(dialog_field.read_only).to be_true
      end
    end

    context "when the automate hash has a value" do
      let(:value) { '1' }

      it_behaves_like "DialogFieldCheckbox#normalize_automate_values"

      it "returns the value in a string format" do
        expect(dialog_field.normalize_automate_values(automate_hash)).to eq("1")
      end
    end

    context "when the automate hash does not have a value" do
      let(:value) { nil }

      it_behaves_like "DialogFieldCheckbox#normalize_automate_values"

      it "sets the value" do
        dialog_field.normalize_automate_values(automate_hash)
        expect(dialog_field.value).to eq(nil)
      end

      it "returns the initial values" do
        expect(dialog_field.normalize_automate_values(automate_hash)).to eq(false)
      end
    end
  end

  describe "#validate" do
    let(:dialog_field_check_box) do
      described_class.new(:label    => 'dialog_field_check_box',
                          :name     => 'dialog_field_check_box',
                          :required => required,
                          :value    => value)
    end
    let(:dialog_tab)   { active_record_instance_double('DialogTab',   :label => 'tab') }
    let(:dialog_group) { active_record_instance_double('DialogGroup', :label => 'group') }

    shared_examples_for "DialogFieldCheckBox#validate that returns nil" do
      it "returns nil" do
        dialog_field_check_box.validate(dialog_tab, dialog_group).should be_nil
      end
    end

    context "when required is true" do
      let(:required) { true }

      context "with a true value" do
        let(:value) { "t" }

        it_behaves_like "DialogFieldCheckBox#validate that returns nil"
      end

      context "with a false value" do
        let(:value) { "f" }

        it "returns error message" do
          dialog_field_check_box.validate(dialog_tab, dialog_group).should eq(
            "tab/group/dialog_field_check_box is required"
          )
        end
      end
    end

    context "when required is false" do
      let(:required) { false }

      context "with a true value" do
        let(:value) { "t" }

        it_behaves_like "DialogFieldCheckBox#validate that returns nil"
      end

      context "with a false value" do
        let(:value) { "f" }

        it_behaves_like "DialogFieldCheckBox#validate that returns nil"
      end
    end
  end

  describe "#refresh_json_value" do
    let(:dialog_field) { described_class.new }

    before do
      DynamicDialogFieldValueProcessor.stub(:values_from_automate).with(dialog_field).and_return("f")
    end

    it "returns the checked value in a hash" do
      expect(dialog_field.refresh_json_value).to eq(:checked => false)
    end

    it "assigns the processed value to value" do
      dialog_field.refresh_json_value
      expect(dialog_field.value).to eq("f")
    end
  end
end
