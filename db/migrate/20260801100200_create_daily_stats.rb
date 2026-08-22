class CreateDailyStats < ActiveRecord::Migration[8.1]
  # Raw checks are pruned after 90 days. Without this table that prune
  # would destroy history permanently, so the roll-up runs before it.
  def change
    create_table :daily_stats do |t|
      t.string  :node, null: false
      t.date    :day,  null: false

      # Minutes are counted, never inferred: expected is what the clock
      # says, observed is what we actually wrote a row for, and the
      # difference is reported rather than absorbed.
      t.integer :expected_minutes, null: false, default: 0
      t.integer :observed_minutes, null: false, default: 0
      t.integer :up_minutes,       null: false, default: 0
      t.integer :degraded_minutes, null: false, default: 0
      t.integer :down_minutes,     null: false, default: 0

      t.float   :p50_ms
      t.float   :p95_ms

      t.timestamps
    end

    add_index :daily_stats, [ :node, :day ], unique: true
  end
end
