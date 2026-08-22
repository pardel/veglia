class CreateOutages < ActiveRecord::Migration[8.1]
  def change
    create_table :outages do |t|
      t.string   :node,       null: false
      # lan_down · dns_down · internet_down · degraded  (observed)
      # app_gap · machine_reboot                        (inferred from a gap)
      t.string   :kind,       null: false
      t.datetime :started_at, null: false
      t.datetime :ended_at
      t.integer  :duration_s
      t.text     :detail

      t.timestamps
    end

    add_index :outages, [ :node, :started_at ]
    # Finding the one open outage per node is the hot path on every check.
    add_index :outages, [ :node, :ended_at ]
  end
end
