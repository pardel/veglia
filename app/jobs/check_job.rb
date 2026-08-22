class CheckJob < ApplicationJob
  queue_as :default

  # A failed check must never take the scheduler down with it: the next
  # minute's run is the recovery. The absence of this row is itself
  # recorded, by GapDetector, on whichever run succeeds next.
  def perform
    CheckRunner.call
  rescue StandardError => e
    Rails.logger.error("[veglia] check failed: #{e.class}: #{e.message}")
    raise if Rails.env.test?
  end
end
