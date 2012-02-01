class Argument < ActiveRecord::Base
	belongs_to :action
	belongs_to :parameter
	@@types = ['Ignore', 'Integer', 'Range', 'C string', 'WC string', 'Pointer', 'Bitmask', 'Blob', 'Not']
	@@masktypes = ['ANY','ALL','EXACT','NONE']

	def to_s
		begin
			typestr = @@types[self.argtype].dup
			case typestr
			when 'Integer'
				typestr = "= #{self.val1.to_s}"
			when 'Not'
				typestr << " #{self.val1.to_s}"
			when 'Range'
				typestr << " #{self.val1.to_s}-#{self.val2.to_s}"
			when 'Bitmask'
				typestr << " {#{@@masktypes[self.val1]} 0x#{self.val2.to_s(16)}}"
			when 'C string'
				typestr << " #{self.regExp}"
			when 'WC string'
				typestr << " #{self.regExp}"
			when 'Pointer'
				typestr << " #{@@masktypes[self.val1]} 0x#{self.val2.to_s(16)}"
			end
			typestr
		rescue
			''
		end
	end

	def setval1(str)
		if str[0..1] == '0x'
			self.val1 = str[2..-1].to_i(16)
		else
			self.val1 = str.to_i
		end
	end

	def setval2(str)
		if String === str and str[0..1] == '0x'
			self.val2 = str[2..-1].to_i(16)
		else
			self.val2 = str.to_i
		end
	end

	# simplified converts the object to a simple array/map/string/int form
	# that can be easily exported/imported to or from formats like YAML
	def simplified(defined)
		simple = {'type' => @@types[self.argtype]}
		case @@types[self.argtype]
		when 'Ignore'
		when 'Integer', 'Not'
			simple['val'] = self.val1
		when 'Range'
			simple['from'] = self.val1
			simple['to'] = self.val2
		when 'C string', 'WC string'
			simple['expression'] = self.regExp
		when 'Pointer', 'Bitmask'
			simple['mask type'] = @@masktypes[self.val1]
			simple['mask'] = self.val2
		when 'Blob'
			simple['size argument'] = self.val2 if self.val1 = -1 or self.val1 == nil
			simple['size'] = self.val1 if self.val2 = 0 or self.val2 == nil
			simple['expression'] = self.regExp
		else
			raise "Error - type #{self.argtype} not supported"
		end
		if not defined
			simple['name'] = self.parameter.name
			simple['paramtype'] = @@types[self.parameter.paramtype]
		end
		simple
	end

	def self.from_simplified(simple, parameter, action)
		arg = Argument.new(:parameter_id => parameter.id, :action => action)

		#get type
		arg.argtype = @@types.index(simple['type'])
		raise Exception.new("Error - invalid argument type; try one of these:\n#{@@types.inspect}") if arg.argtype == nil

		case simple['type']
		when 'Ignore'
		when 'Integer', 'Not'
			arg.val1 = simple["val"]
		when 'Range'
			arg.sval1 = simple["from"]
			arg.sval2 = simple["to"]
		when 'C string', 'WC string'
			arg.regExp = simple["expression"]
		when 'Pointer', 'Bitmask'
			arg.val1 = @@masktypes.index simple['mask type']
			arg.val2 = simple['mask']
		when 'Blob'
			arg.regExp = simple["expression"]
			if simple.has_key? 'argument'
				arg.val2 = simple['argument'] 
				arg.val1 = -1
			elsif simple.has_key? 'size'
				arg.val1 = simple['size']
				arg.val2 = 0
			else
				raise Exception.new('Error - must provide blob argument or size')
			end
		else
			raise Exception.new("Error - type #{self.argtype} not supported")
		end
		arg.save
		arg
	end

	def compiled
		out = [self.argtype].pack("V")
		case @@types[self.argtype]
		when 'Ignore'
		when 'Integer', 'Not'
			raise 'Error - invalid integer' if self.val1 == nil
			out << [self.val1].pack("Q")
		when 'Range'
			raise 'Error - invalid range' if self.val1 == nil or self.val2 == nil
			out << [self.val1, self.val2].pack("QQ")
		when 'C string'
			raise 'Error - invalid C string' if self.regExp == nil
			stringVal = self.regExp+("\x00"*(4-(self.regExp.length % 4)))
			out << [stringVal.length].pack("V*") + stringVal
		when 'WC string'
			raise 'Error - invalid wide char string' if self.regExp == nil
			binaryVal = (self.regExp + "\x00").encode("UTF-16LE").force_encoding('binary')
			stringVal = binaryVal + ("\x00" * (4 - (self.regExp.length % 4)))
			out << [stringVal.length].pack("V*") + stringVal
		when 'Pointer'
			self.val1 = 0 if self.val1 == nil
			raise "Error - invalid argument type for Pointer mode argument" if self.val2 == nil
			out << [self.val1, self.val2].pack("V*")
		when 'Bitmask'
			self.val1 = 0 if self.val1 == nil
			raise "Error - invalid argument type for Bitmask mask argument" if self.val2 == nil
			out << [self.val1, self.val2].pack("VQ")
		when 'Blob'
			if (self.val1 == -1 and self.val2 == 0) or self.val1 == nil or self.val2 == nil #insufficient info
				out = [0].pack("V") # ignore
			else
				# if not a number, must be a ref
				self.val1 = -1 if self.val1 == nil
				self.val2 = 0 if self.val2 == nil
				stringVal = self.regExp+("\x00"*(4-(self.regExp.length % 4)))
				out << [self.val1, self.val2, stringVal.length].pack("V*") + stringVal
			end
		else
			raise "Error - type #{self.argtype} not supported"
		end
		# size, type, value
		[out.size + 4].pack("V*") + out
	end
end
