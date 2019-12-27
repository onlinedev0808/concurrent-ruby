require_relative 'struct_shared'

module Concurrent
  RSpec.describe MutableStruct do

    it_should_behave_like :struct
    it_should_behave_like :mergeable_struct

    let(:anonymous) { described_class.new(:name, :address, :zip) }
    let!(:customer) { described_class.new('Customer', :name, :address, :zip) }
    let(:joe)       { customer.new('Joe Smith', '123 Maple, Anytown NC', 12345) }

    subject { anonymous.new('Joe Smith', '123 Maple, Anytown NC', 12345) }

    context 'definition' do

      it 'defines a setter for each member' do
        members = [:Foo, :bar, 'baz']
        structs = [
          described_class.new(*members).new,
          described_class.new('ClassForCheckingSetterDefinition', *members).new
        ]

        structs.each do |struct|
          members.each do |member|
            func = "#{member}="
            expect(struct).to respond_to func
            method = struct.method(func)
            expect(method.arity).to eq 1
          end
        end
      end
    end

    context '#[member]=' do

      it 'sets the value when given a valid symbol member' do
        expect(joe[:name] = 'Jane').to eq 'Jane'
        expect(subject[:name] = 'Jane').to eq 'Jane'
      end

      it 'sets the value when given a valid string member' do
        expect(joe['name'] = 'Jane').to eq 'Jane'
        expect(subject['name'] = 'Jane').to eq 'Jane'
      end

      it 'raises an exception when given a non-existent symbol member' do
        expect{joe[:fooarbaz] = 'Jane'}.to raise_error(NameError)
        expect{subject[:fooarbaz] = 'Jane'}.to raise_error(NameError)
      end

      it 'raises an exception when given a non-existent string member' do
        expect{joe['fooarbaz'] = 'Jane'}.to raise_error(NameError)
        expect{subject['fooarbaz'] = 'Jane'}.to raise_error(NameError)
      end
    end

    context '#[index]=' do

      it 'sets the value when given a valid index' do
        expect(joe[0] = 'Jane').to eq 'Jane'
        expect(subject[0] = 'Jane').to eq 'Jane'
      end

      it 'raises an exception when given an out-of-bound index' do
        expect{joe[100] = 'Jane'}.to raise_error(IndexError)
        expect{subject[100] = 'Jane'}.to raise_error(IndexError)
      end
    end

    context 'synchronization' do

      it 'protects #values' do
        expect(subject).to receive(:synchronize).at_least(:once).with(no_args).and_call_original
        subject.values
      end

      it 'protects #values_at' do
        expect(subject).to receive(:synchronize).at_least(:once).with(no_args).and_call_original
        subject.values_at(0)
      end

      it 'protects #[index]' do
        expect(subject).to receive(:synchronize).at_least(:once).with(no_args).and_call_original
        subject[0]
      end

      it 'protects #[member]' do
        expect(subject).to receive(:synchronize).at_least(:once).with(no_args).and_call_original
        subject[:name]
      end

      it 'protects getter methods' do
        expect(subject).to receive(:synchronize).at_least(:once).with(no_args).and_call_original
        subject.name
      end

      it 'protects #[index]=' do
        expect(subject).to receive(:synchronize).at_least(:once).with(no_args).and_call_original
        subject[0] = :foo
      end

      it 'protects #[member]=' do
        expect(subject).to receive(:synchronize).at_least(:once).with(no_args).and_call_original
        subject[:name] = :foo
      end

      it 'protects getter methods' do
        expect(subject).to receive(:synchronize).at_least(:once).with(no_args).and_call_original
        subject.name = :foo
      end

      it 'protects #to_s' do
        expect(subject).to receive(:synchronize).at_least(:once).with(no_args).and_call_original
        subject.to_s
      end

      it 'protects #inspect' do
        expect(subject).to receive(:synchronize).at_least(:once).with(no_args).and_call_original
        subject.inspect
      end

      it 'protects #merge' do
        expect(subject).to receive(:synchronize).at_least(:once).with(no_args).and_call_original
        subject.merge(subject.members.first => subject.values.first)
      end

      it 'protects #to_h' do
        expect(subject).to receive(:synchronize).at_least(:once).with(no_args).and_call_original
        subject.to_h
      end

      it 'protects #==' do
        expect(subject).to receive(:synchronize).at_least(:once).with(no_args).and_call_original
        subject == joe
      end

      it 'protects #each' do
        expect(subject).to receive(:synchronize).at_least(:once).with(no_args).and_call_original
        subject.each{|value| nil }
      end

      it 'protects #each_pair' do
        expect(subject).to receive(:synchronize).at_least(:once).with(no_args).and_call_original
        subject.each_pair{|member, value| nil }
      end

      it 'protects #select' do
        expect(subject).to receive(:synchronize).at_least(:once).with(no_args).and_call_original
        subject.select{|value| false }
      end

      it 'protects #initialize_copy' do
        expect(subject).to receive(:synchronize).at_least(:once).with(no_args).and_call_original
        subject.clone
      end
    end

    context 'copy' do
      context '#dup' do
        it 'mutates only the copy' do
          expect(subject.dup.name = 'Jane').not_to eq(subject.name)
        end
      end

      context '#clone' do
        it 'mutates only the copy' do
          expect(subject.clone.name = 'Jane').not_to eq(subject.name)
        end
      end
    end
  end
end
