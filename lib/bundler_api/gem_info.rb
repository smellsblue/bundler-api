require 'bundler_api'

# Return data about all the gems: all gem names, all versions of all gems, all dependencies for all versions of a gem
class BundlerApi::GemInfo
  DepKey = Struct.new(:name, :number, :platform)

  def initialize(connection)
    @conn = connection
  end

  # @param [String] array of strings with the gem names
  def deps_for(gems = [])
    dataset =
      if gems.any?
        @conn[<<-SQL, Sequel.value_list(gems)]
          SELECT rv.name, rv.number, rv.platform, d.requirements, for_dep_name.name dep_name
          FROM
            (SELECT r.name, v.number, v.platform, v.id AS version_id
            FROM rubygems AS r, versions AS v
            WHERE v.rubygem_id = r.id
              AND v.indexed is true
              AND r.name IN ?) AS rv
          LEFT JOIN dependencies AS d ON
            d.version_id = rv.version_id
          LEFT JOIN rubygems AS for_dep_name ON
            d.rubygem_id = for_dep_name.id
            AND d.scope = 'runtime';
        SQL
      else
        @conn[<<-SQL]
          SELECT rv.name, rv.number, rv.platform, d.requirements, for_dep_name.name dep_name
          FROM
            (SELECT r.name, v.number, v.platform, v.id AS version_id
            FROM rubygems AS r, versions AS v
            WHERE v.rubygem_id = r.id
              AND v.indexed is true) AS rv
          LEFT JOIN dependencies AS d ON
            d.version_id = rv.version_id
          LEFT JOIN rubygems AS for_dep_name ON
            d.rubygem_id = for_dep_name.id
            AND d.scope = 'runtime';
SQL
      end

    deps = {}

    dataset.each do |row|
      key = DepKey.new(row[:name], row[:number], row[:platform])
      deps[key] = [] unless deps[key]
      deps[key] << [row[:dep_name], row[:requirements]] if row[:dep_name]
    end

    deps.map do |dep_key, gem_deps|
      {
        name:         dep_key.name,
        number:       dep_key.number,
        platform:     dep_key.platform,
        dependencies: gem_deps
      }
    end
  end

  # return list of gem names
  def names
    @conn[:rubygems].select(:name).order(:name).all.map {|r| r[:name] }
  end

  # return a list of gem names and their versions
  def versions
    specs_hash = Hash.new {|h, k| h[k] = [] }
    rows = @conn[<<-SQL]
      SELECT v.full_name
      FROM versions AS v
      WHERE v.indexed is true
SQL
    rows.each do |row|
      full_name = row[:full_name]
      rindex = full_name.rindex("-")
      name, version = full_name[0..(rindex - 1)], full_name[(rindex + 1)..-1]
      specs_hash[name] << version
    end

    specs_hash.each {|k, v| v.sort! }
  end
end
