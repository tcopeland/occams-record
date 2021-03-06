module OccamsRecord
  # ActiveRecord's internal type casting API changes from version to version.
  TYPE_CAST_METHOD = case ActiveRecord::VERSION::MAJOR
                     when 4 then :type_cast_from_database
                     when 5 then :deserialize
                     end

  #
  # Dynamically build a class for a specific set of result rows. It inherits from OccamsRecord::ResultRow, and optionall includes
  # a user-defined module.
  #
  # @param model [ActiveRecord::Base] the AR model representing the table (it holds column & type info).
  # @param column_names [Array<String>] the column names in the result set. The order MUST match the order returned by the query.
  # @param association_names [Array<String>] names of associations that will be eager loaded into the results.
  # @param included_module [Module] (optional)
  # @return [OccamsRecord::ResultRow] a class customized for this result set
  #
  def self.build_result_row_class(model, column_names, association_names, included_module = nil)
    Class.new(ResultRow) do
      include included_module if included_module

      self.columns = column_names.map(&:to_s)
      self.associations = association_names.map(&:to_s)
      self.model_name = model.name

      # Build getters & setters for associations. (We need setters b/c they're set AFTER the row is initialized
      attr_accessor(*association_names)

      # Build a getter for each attribute returned by the query. The values will be type converted on demand.
      column_names.each_with_index do |col, idx|
        type = model.attributes_builder.types[col.to_s] || raise("OccamsRecord: Column `#{col}` does not exist on model `#{model.name}`")
        define_method col do
          @cast_values_cache[idx] ||= type.send(TYPE_CAST_METHOD, @raw_values[idx])
        end
      end
    end
  end

  #
  # Abstract class for result rows.
  #
  class ResultRow
    class << self
      # Array of column names
      attr_accessor :columns
      # Array of associations names
      attr_accessor :associations
      # Name of Rails model
      attr_accessor :model_name
    end
    self.columns = []
    self.associations = []

    #
    # Initialize a new result row.
    #
    # @param raw_values [Array] array of raw values from db
    #
    def initialize(raw_values)
      @raw_values = raw_values
      @cast_values_cache = {}
    end

    #
    # Return row as a Hash (recursive).
    #
    # @param symbolize_names [Boolean] if true, make Hash keys Symbols instead of Strings
    # @return [Hash] a Hash with String or Symbol keys
    #
    def to_h(symbolize_names: false)
      hash = self.class.columns.reduce({}) { |a, col_name|
        key = symbolize_names ? col_name.to_sym : col_name
        a[key] = send col_name
        a
      }

      self.class.associations.reduce(hash) { |a, assoc_name|
        key = symbolize_names ? assoc_name.to_sym : assoc_name
        assoc = send assoc_name
        a[key] = if assoc.is_a? Array
                   assoc.map { |x| x.to_h(symbolize_names: symbolize_names) }
                 elsif assoc
                   assoc.to_h(symbolize_names: symbolize_names)
                 end
        a
      }
    end

    alias_method :to_hash, :to_h
  end
end
