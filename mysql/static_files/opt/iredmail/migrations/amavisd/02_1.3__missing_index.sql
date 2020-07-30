-- https://docs.iredmail.org/upgrade.iredmail.1.2.1-1.3.html#mysqlmariadb-backend-special
CREATE INDEX msgs_idx_time_iso ON msgs (time_iso);