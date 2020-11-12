module Formulario
  def self.load(spec)
    Formulario::Form.new spec[:fields].map { |it| Formulario::Field.load it }
  end

  class Form
    attr_reader :fields

    def initialize(fields)
      @fields = fields
    end

    def size
      @fields.size
    end
  end

  class Field
    attr_reader :name, :validations

    def initialize(name:, validations:)
      raise 'Missing field name' unless name
      @name = name
      @validations = validations
    end


    def self.load(spec)
      class_for(spec[:type]).new name: spec[:name], validations: (spec[:validate] || []).map { |it| Formulario::Validation.parse it }
    end

    def self.custom_field_types
      @custom_field_types ||= {}
    end

    def self.class_for(type)
      case type
      when :number then Formulario::NumberField
      when :text then Formulario::TextField
      when :text_area then Formulario::TextArea
      else custom_field_types[type] || (raise "Unsupported field #{type}")
      end
    end

    def self.support_custom_field_type?(field_type)
      custom_field_types.include? field_type
    end


    def self.register_custom_field_class!(klass)
      custom_field_types[klass.field_type] = klass
    end

    def self.unregister_custom_field_class!(klass)
      custom_field_types.delete klass.field_type
    end

  end

  class TextField < Field

  end

  class NumberField < Field
  end

  class TextArea < Field
  end

  module Validation
    def self.parse(spec)
      Formulario::Validation::Regexp.new
    end

    class Regexp
    end
  end
end


describe Formulario do
  it "has a version number" do
    expect(Formulario::VERSION).not_to be nil
  end

  describe 'form definition' do
    describe 'fields' do
      subject { Formulario.load(fields: []) }

      context 'no fields' do
        it { expect(subject).to be_a Formulario::Form }
        it { expect(subject.size).to eq 0 }
      end

      context 'one field' do
        context 'invalid text field' do
          subject { Formulario.load(fields: [{type: :text}]) }

          it { expect { subject }.to raise_error 'Missing field name' }
        end

        context 'text field' do
          subject { Formulario.load(fields: [{type: :text, name: 'username'}]) }

          it { expect(subject.size).to eq 1 }
          it { expect(subject.fields.first).to be_a Formulario::Field }
          it { expect(subject.fields.first).to be_a Formulario::TextField }
          it { expect(subject.fields.first.name).to eq "username" }
          it { expect(subject.fields.first.validations.size).to eq 0 }
        end


        context 'text field with regexp validation' do
          subject { Formulario.load(fields: [{type: :text, name: 'username', validate: {regexp: "\w{4}"} }]).fields.first }

          it { expect(subject.validations.size).to eq 1 }
          it { expect(subject.validations.first).to be_a Formulario::Validation::Regexp }
        end

        context 'number field' do
          subject { Formulario.load(fields: [{type: :number, name: 'age'}]).fields.first }

          it { expect(subject).to be_a Formulario::Field }
          it { expect(subject).to be_a Formulario::NumberField }
          it { expect(subject.name).to eq 'age' }

        end

        context 'text area' do
          subject { Formulario.load(fields: [{type: :text_area, name: 'description'}]) }

          it { expect(subject.fields.first).to be_a Formulario::TextArea }
          it { expect(subject.fields.first.name).to eq 'description' }

        end

        context 'custom' do
          class MyCustomField < Formulario::Field
            def self.field_type
              :my_custom_field
            end
          end

          before { Formulario::Field.register_custom_field_class! MyCustomField }
          after { Formulario::Field.unregister_custom_field_class! MyCustomField }

          subject { Formulario.load(fields: [{type: :my_custom_field, name: 'foo'}]) }

          it { expect(Formulario::Field.support_custom_field_type? :my_custom_field).to be true }
          it { expect(Formulario::Field.custom_field_types.size).to eq 1 }
          it { expect(subject.fields.first).to be_a MyCustomField }
          it { expect(subject.fields.first.name).to eq 'foo' }
        end


        context 'unsupported field type' do
          subject { Formulario.load(fields: [{type: :other}]) }

          it { expect { subject }.to raise_error 'Unsupported field other' }
        end
      end
    end

    describe 'full form' do
      subject do
        Formulario.load(
          name: 'myform',
          display_name: 'A great form',
          max_anwsers: 100,
          allow_edit: true,
          start_date: '2020-10-5',
          end_date: '2020-12-30',
          captcha: true,
          save: {
            local: true
            database: true,
            exec: 'my_custom_code'
          }
          fields: [
            {
              type: :text,
              name: 'username',
              validate: {
                nonblank: true
                regexp: "\w{4}",
                unique: true
              },
              normalize: {
                downcase: true,
                exec: 'my_custom_code'
              },
              confirm: true,
              required: true
            },
            {type: :text, name: 'personal_id', validate: {regexp: "\d{8,9}", unique: true, exec: 'my_custom_code' } }
          ])
      end

      pending
    end
  end
end
