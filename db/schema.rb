# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_08_02_090000) do
  create_table "checks", force: :cascade do |t|
    t.datetime "boot_at"
    t.datetime "checked_at", null: false
    t.datetime "created_at", null: false
    t.text "detail"
    t.float "dns_ms"
    t.boolean "dns_ok"
    t.string "gateway_ip"
    t.float "gateway_ms"
    t.boolean "gateway_ok"
    t.float "http_ms"
    t.integer "http_ok_count"
    t.integer "http_total"
    t.string "node", null: false
    t.string "status", null: false
    t.datetime "updated_at", null: false
    t.index ["checked_at"], name: "index_checks_on_checked_at"
    t.index ["node", "checked_at"], name: "index_checks_on_node_and_checked_at"
  end

  create_table "daily_stats", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.date "day", null: false
    t.integer "degraded_minutes", default: 0, null: false
    t.integer "down_minutes", default: 0, null: false
    t.integer "expected_minutes", default: 0, null: false
    t.string "node", null: false
    t.integer "observed_minutes", default: 0, null: false
    t.float "p50_ms"
    t.float "p95_ms"
    t.integer "up_minutes", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["node", "day"], name: "index_daily_stats_on_node_and_day", unique: true
  end

  create_table "outages", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "detail"
    t.integer "duration_s"
    t.datetime "ended_at"
    t.string "kind", null: false
    t.string "node", null: false
    t.datetime "started_at", null: false
    t.datetime "updated_at", null: false
    t.index ["node", "ended_at"], name: "index_outages_on_node_and_ended_at"
    t.index ["node", "kind", "started_at"], name: "index_outages_on_node_and_kind_and_started_at", unique: true
    t.index ["node", "started_at"], name: "index_outages_on_node_and_started_at"
  end
end
