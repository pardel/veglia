require "open3"

# The kernel's boot timestamp, which is the only evidence that
# distinguishes "the machine rebooted" from "the app died" across a gap
# in the record. Without it, both look identical: an absence of rows.
module BootTime
  def self.call
    out, _err, status = Open3.capture3("/usr/sbin/sysctl", "-n", "kern.boottime")
    return nil unless status.success?

    # macOS prints: { sec = 1784039581, usec = 536265 } Tue Jul 14 15:33:01 2026
    seconds = out[/sec\s*=\s*(\d+)/, 1]
    seconds && Time.zone.at(seconds.to_i)
  rescue Errno::ENOENT
    # Not macOS. Veglia still runs, it just cannot tell a reboot from a
    # crash, and says so rather than guessing.
    nil
  end
end
