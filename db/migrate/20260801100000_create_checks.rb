class CreateChecks < ActiveRecord::Migration[8.1]
  def change
    create_table :checks do |t|
      # Which vantage point observed this. Present from the first
      # migration so a second Mini needs no schema change.
      t.string   :node,          null: false
      t.datetime :checked_at,    null: false
      t.string   :status,        null: false

      # Tier 1 — the default gateway. Separates "my router/Wi-Fi is
      # broken" from "my ISP is broken".
      t.boolean  :gateway_ok
      t.float    :gateway_ms
      t.string   :gateway_ip

      # Tier 2 — name resolution, timed independently of HTTP.
      t.boolean  :dns_ok
      t.float    :dns_ms

      # Tier 3 — HTTP reachability across independent endpoints. Stored
      # as a count rather than a boolean so the quorum is auditable
      # after the fact.
      t.integer  :http_ok_count
      t.integer  :http_total
      t.float    :http_ms

      # The kernel boot time at the moment of the check. This is what
      # lets a later check tell a reboot from a crash across a gap.
      t.datetime :boot_at

      t.text     :detail

      t.timestamps
    end

    add_index :checks, [ :node, :checked_at ]
    add_index :checks, :checked_at
  end
end
