require 'time'
require 'active_support/all'

module Formulario
  def self.load(spec)
    Formulario::Form.new(
      name: spec[:name],
      display_name: spec[:display_name],
      max_anwsers: spec[:max_anwsers],
      start_date: datetime(spec[:start_date]),
      end_date: datetime(spec[:end_date]),
      fields: spec[:fields].to_a.map { |it| Formulario::Field.load it }
    )
  end

  def self.datetime(datetime)
    datetime.is_a?(String) ? DateTime.iso8601(datetime) : datetime
  end

  class Form
    attr_reader :name, :display_name
    attr_reader :start_date, :end_date, :max_anwsers
    attr_reader :fields

    def initialize(name:, display_name: nil, start_date: nil, max_anwsers: nil, end_date: nil, fields:)
      @fields = fields
      @name = name
      @display_name = display_name
      @max_anwsers = max_anwsers
      @start_date = start_date
      @end_date = end_date
    end

    def size
      @fields.size
    end

    def normalize(answer)
      answer.map { |k, v| [k, fields.find { |it| it.name.to_s == k.to_s }.normalize(v)] }.to_h
    end

    def validate(answer)
      {}
    end
  end

  module WithExtensions
    def extensions
      @extensions ||= {}
    end

    def support_extension_type?(extension_type)
      extensions.include? extension_type
    end


    def register_extension_class!(klass)
      extensions[klass.extension_type] = klass
    end

    def unregister_extension_class!(klass)
      extensions.delete klass.extension_type
    end

  end

  class Field
    extend WithExtensions

    attr_reader :name, :validations, :normalizations

    def initialize(name:, required: false, confirm: false, validations: [], normalizations: [])
      raise 'Missing field name' unless name
      @name = name
      @required = required
      @confirm = confirm
      @validations = validations
      @normalizations = normalizations
    end

    def required?
      @required
    end

    def confirm?
      @confirm
    end

    def normalize(value)
      normalizations.inject(value) { |accum, it| it.normalize(accum) }
    end

    def self.load(spec)
      class_for(spec[:type]).new(
        name: spec[:name],
        required: spec[:required],
        confirm: spec[:confirm],
        normalizations: spec[:normalize].to_a.map { |it| Formulario::Normalization.parse(*it) },
        validations: spec[:validate].to_a.map { |it| Formulario::Validation.parse(*it) }
      )
    end

    def self.class_for(type)
      case type
      when :number then Formulario::NumberField
      when :text then Formulario::TextField
      when :text_area then Formulario::TextArea
      else extensions[type] || (raise "Unsupported field #{type}")
      end
    end
  end

  class TextField < Field
  end

  class NumberField < Field
  end

  class TextArea < Field
  end

  module ExecLike
    attr_reader :command
    def initialize(command)
      @command = command
    end
  end

  module Normalization
    extend WithExtensions

    def self.parse(type, spec)
      case type
      when :downcase then Formulario::Normalization::Downcase
      when :trim then Formulario::Normalization::Trim
      when :squeeze then Formulario::Normalization::Squeeze
      when :exec then Formulario::Normalization::Exec.new(spec)
      else extensions[type]&.new(spec) || (raise "Unsupported normalization #{type}")
      end
    end

    module Downcase
      def self.normalize(value)
        value.downcase
      end
    end

    module Trim
    end

    module Squeeze
    end

    class Exec
      include ExecLike
    end
  end

  module Validation
    extend WithExtensions

    def self.parse(type, spec)
      case type
      when :regexp then Formulario::Validation::Regexp.new(/#{spec}/)
      when :unique then Formulario::Validation::Unique
      when :nonblank then Formulario::Validation::NonBlank
      when :exec then Formulario::Validation::Exec.new(spec)
      else extensions[type]&.new(spec) || (raise "Unsupported validation #{type}")
      end
    end

    class Regexp
      attr_reader :pattern

      def initialize(pattern)
        @pattern = pattern
      end
    end

    class Exec
      include ExecLike
    end

    module Unique
    end

    module NonBlank
      def self.validate(value, _context)
      end
    end
  end
end


describe Formulario do
  it "has a version number" do
    expect(Formulario::VERSION).not_to be nil
  end

  describe 'form evaluation' do
    subject do
      Formulario.load(
        fields: [
          {
            type: :text,
            name: 'username',
            validate: {regexp: '\w{4}'},
            normalize: {downcase: true}
          }
        ]
      )
    end

    pending { expect(subject.render).to eq '<form></form>' }
    it { expect(subject.normalize username: 'FooO').to eq username: 'fooo' }

    it { expect(subject.validate username: 'Fooo').to eq({}) }
    pending { expect(subject.validate username: 'Foooz').to eq username: 'does not match validation expression' }
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
          subject do
            Formulario.load(fields: [{type: :text, name: 'username', validate: {regexp: '\w{4}'} }]).fields.first.validations
          end

          it { expect(subject.size).to eq 1 }
          it { expect(subject.first).to be_a Formulario::Validation::Regexp }
          it { expect(subject.first.pattern).to eq /\w{4}/ }
        end

        context 'text field with unique, non-blank validation' do
          subject do
            Formulario.load(fields: [
              {type: :text, name: 'username', validate: {unique: true, nonblank: true} }
            ]).fields.first.validations
          end

          it { expect(subject.size).to eq 2 }
          it { expect(subject.first).to be Formulario::Validation::Unique }
          it { expect(subject.second).to be Formulario::Validation::NonBlank }
        end

        context 'text field with exec validation' do
          subject do
            Formulario.load(fields: [
              {type: :text, name: 'username', validate: {exec: 'a command'} }
            ]).fields.first.validations
          end

          it { expect(subject.first).to be_a Formulario::Validation::Exec }
          it { expect(subject.first.command).to eq 'a command' }
        end

        context 'text field with exec normalization' do
          subject do
            Formulario.load(fields: [
              {type: :text, name: 'username', normalize: {exec: 'a command'} }
            ]).fields.first.normalizations
          end

          it { expect(subject.first).to be_a Formulario::Normalization::Exec }
          it { expect(subject.first.command).to eq 'a command' }
        end

        context 'text field with string normalizations' do
          subject do
            Formulario.load(fields: [
              {type: :text, name: 'username', normalize: {downcase: true, trim: true, squeeze: true} }
            ]).fields.first.normalizations
          end

          it { expect(subject.first).to be Formulario::Normalization::Downcase }
          it { expect(subject.second).to be Formulario::Normalization::Trim }
          it { expect(subject.third).to be Formulario::Normalization::Squeeze }
        end

        context 'text field with custom normalization' do
          class MyCustomNormalization
            def initialize(_)
            end
            def self.extension_type
              :my_custom_normalization
            end
          end

          before { Formulario::Normalization.register_extension_class! MyCustomNormalization }
          after { Formulario::Normalization.unregister_extension_class! MyCustomNormalization }

          subject do
            Formulario.load(fields: [
              {type: :text, name: 'username', normalize: {my_custom_normalization: true} }
            ]).fields.first.normalizations
          end

          it { expect(Formulario::Normalization.extensions.size).to eq 1 }
          it { expect(Formulario::Normalization.support_extension_type? :my_custom_normalization).to be true }

          it { expect(subject.size).to eq 1 }
          it { expect(subject.first).to be_a MyCustomNormalization }
        end


        context 'text field with custom validation' do
          class MyCustomValidation
            attr_reader :value
            def initialize(value)
              @value = value
            end
            def self.extension_type
              :my_custom_validation
            end
          end

          before { Formulario::Validation.register_extension_class! MyCustomValidation }
          after { Formulario::Validation.unregister_extension_class! MyCustomValidation }

          subject do
            Formulario.load(fields: [
              {type: :text, name: 'username', validate: {my_custom_validation: 'sample'} }
            ]).fields.first.validations
          end

          it { expect(subject.size).to eq 1 }
          it { expect(subject.first).to be_a MyCustomValidation }
          it { expect(subject.first.value).to eq 'sample' }
        end

        context 'number field' do
          subject { Formulario.load(fields: [{type: :number, name: 'age'}]).fields.first }

          it { expect(subject).to be_a Formulario::Field }
          it { expect(subject).to be_a Formulario::NumberField }
          it { expect(subject.name).to eq 'age' }

        end

        context 'number field with confirm and required' do
          subject { Formulario.load(fields: [{type: :number, name: 'age', confirm: true, required: true}]).fields.first }

          it { expect(subject.confirm?).to be true }
          it { expect(subject).to be_required }
        end


        context 'text area' do
          subject { Formulario.load(fields: [{type: :text_area, name: 'description'}]) }

          it { expect(subject.fields.first).to be_a Formulario::TextArea }
          it { expect(subject.fields.first.name).to eq 'description' }
        end

        context 'custom' do
          class MyCustomField < Formulario::Field
            def self.extension_type
              :my_extension
            end
          end

          before { Formulario::Field.register_extension_class! MyCustomField }
          after { Formulario::Field.unregister_extension_class! MyCustomField }

          subject { Formulario.load(fields: [{type: :my_extension, name: 'foo'}]) }

          it { expect(Formulario::Field.support_extension_type? :my_extension).to be true }
          it { expect(Formulario::Field.extensions.size).to eq 1 }
          it { expect(subject.fields.first).to be_a MyCustomField }
          it { expect(subject.fields.first.name).to eq 'foo' }
        end


        context 'unsupported field type' do
          subject { Formulario.load(fields: [{type: :other}]) }

          it { expect { subject }.to raise_error 'Unsupported field other' }
        end
      end
    end

    describe 'descriptive fields' do
      subject { Formulario.load(name: 'myform', display_name: 'A great form') }

      it { expect(subject.name).to eq 'myform' }
      it { expect(subject.display_name).to eq 'A great form' }
    end

    describe 'form limit fields' do
      subject { Formulario.load(max_anwsers: 100, start_date: '2020-01-05', end_date: '2020-01-15T23:59:00-03' ) }

      it { expect(subject.max_anwsers).to eq 100 }
      it { expect(subject.start_date).to eq DateTime.new(2020, 1, 5) }
      it { expect(subject.end_date).to eq DateTime.new(2020, 1, 15, 23, 59, 0, '-3') }
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
            local: true,
            database: true,
            exec: 'my_custom_code'
          },
          fields: [
            {
              type: :text,
              name: 'username',
              validate: {
                nonblank: true,
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
            {type: :text, name: 'personal_id', validate: {regexp: '\d{8,9}', unique: true, exec: 'my_custom_code' } }
          ])
      end

      pending
    end
  end
end
