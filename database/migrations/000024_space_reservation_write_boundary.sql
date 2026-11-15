-- Keep space reservation lifecycle writes behind narrow database commands.
-- Runtime may create an occupancy claim, but cannot mutate or delete an
-- existing claim directly. Expiry and cancellation commands execute as the
-- controlled SECURITY DEFINER owner functions.
REVOKE UPDATE, DELETE ON eogp.venue_space_time_blocks
  FROM eventor_runtime, eventor_worker;
