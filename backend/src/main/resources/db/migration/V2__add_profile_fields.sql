-- about_me and avatar_file_name hold plain profile data for now. A future
-- security phase may encrypt about_me (and possibly email) at rest; both
-- columns stay as opaque VARCHARs so that migration requires no schema
-- change, only a value-encoding change in the application layer.
ALTER TABLE users ADD COLUMN about_me VARCHAR(500);
ALTER TABLE users ADD COLUMN avatar_file_name VARCHAR(255);
