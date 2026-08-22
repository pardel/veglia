# One hole in the record is one row, enforced by the database rather
# than by hoping two threads never look at once.
#
# CheckRunner reads the last stored check and then asks GapDetector
# whether a gap precedes it, with nothing between the read and the
# write. That is fine at one check a minute and wrong the moment two
# run together, which is exactly what happens on recovery: while the
# app is down the scheduler banks the minutes it missed, and when it
# comes back the worker's three threads take three of them at once.
# All three see the same stale previous check, all three conclude a gap
# preceded it, and all three write it down. The live database had 41
# rows describing 20 spans, in groups of two and three, always created
# within a few milliseconds of each other.
#
# The duplicates are deleted lowest-id-first before the index goes on,
# since the index cannot be created while they are there. Nothing is
# lost: rows sharing a node, a kind and a start instant are the same
# gap observed more than once, not two gaps.
class EnforceOneOutagePerSpan < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      DELETE FROM outages
      WHERE id NOT IN (SELECT MIN(id) FROM outages GROUP BY node, kind, started_at)
    SQL

    add_index :outages, [ :node, :kind, :started_at ],
              unique: true,
              name: "index_outages_on_node_and_kind_and_started_at"
  end

  def down
    remove_index :outages, name: "index_outages_on_node_and_kind_and_started_at"
  end
end
