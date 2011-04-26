class Pool
	def initialize(cmd, start_port, min_size, max_size)
		@free = []
		@inuse = []
		@highest_port = start_port-1
		@cmd = cmd
		@min = min_size
		@max = max_size
		ensure_min
	end

	def ensure_min
		EM::schedule {
			count = @free.length + @inuse.length
			if count < @min
				count.upto(@min-1) do
					spawn
				end
			end
		}
	end

	def shutdown
		@min = 0
		@max = 0
	end

	def spawn
		port = (@highest_port += 1)
		EM::system(@cmd.gsub(/\$PORT/, port.to_s)) { |output, status|
			# NOTE: this code assumes the child runs non-daemonized
			self.kill(port)
		}
		EM::schedule {
			@free << port
		}
	end

	def next(&blk)
		EM::schedule {
			if (port = @free.shift)
				@inuse << port
				blk.call(port)
			else
				# All current children are in use
				spawn if (@inuse.length < @max)
				EM::next_tick {
					self.next &blk
				}
			end
		}
	end

	def kill(port)
		EM::schedule {
			@free.delete(port)
			@inuse.delete(port)
			ensure_min
		}
	end

	def done_with(port)
		EM::schedule {
			@free << port if @inuse.delete(port)
		}
	end
end
