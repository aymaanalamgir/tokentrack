# Docker bootstraps the schema and its owner. The application role can create
# objects inside business, but deliberately cannot create database-level schemas.
# Keep Rails' normal SQL dump/load flow while leaving schema creation to bootstrap.
Rake::Task["db:schema:dump"].enhance do
  path = Rails.root.join("db/structure.sql")
  if path.exist?
    contents = path.read
    path.write(contents.sub(/^CREATE SCHEMA business;\n/, "-- business schema is provisioned by Docker initialization.\n"))
  end
end
