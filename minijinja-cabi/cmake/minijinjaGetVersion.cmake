# Get minijinja version from Cargo.toml

# 1. Get the absolute path to Cargo.toml, which is one directory up.
#    CMAKE_CURRENT_LIST_DIR is the key variable here.
get_filename_component(CARGO_TOML_PATH "${CMAKE_CURRENT_LIST_DIR}/../Cargo.toml" ABSOLUTE)

# 2. Read the contents of the file
file(READ "${CARGO_TOML_PATH}" CARGO_TOML_CONTENTS)

# 3. Use a regular expression to find the version line and capture the version number
# This looks for 'version = "x.y.z"' and saves "x.y.z"
string(REGEX MATCH "version[ \t]*=[ \t]*\"([0-9\.]+)\""
    CARGO_VERSION_MATCH "${CARGO_TOML_CONTENTS}")

# 4. The captured version is in the special variable CMAKE_MATCH_1.
# We assign it to our own variable for clarity and error check it.
set(MINIJINJA_VERSION "${CMAKE_MATCH_1}")
if(NOT MINIJINJA_VERSION)
    message(FATAL_ERROR "❌ Could not parse minijinja version from Cargo.toml")
endif()
