class MaintenanceJob < ApplicationJob
  queue_as :default

  def perform
    Rollup.call
  end
end
