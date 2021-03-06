require 'test_helper'

class QueryTest < Minitest::Test
  include TestHelpers

  def setup
    DatabaseCleaner.start
  end

  def teardown
    DatabaseCleaner.clean
  end

  def test_initializes_correctly
    q = OccamsRecord::Query.new(Category.all)
    assert_equal Category, q.model
    assert_match %r{SELECT}, q.scope.to_sql
    refute_nil q.conn
  end

  def test_simple_query
    results = OccamsRecord.query(Category.all.order('name')).run
    assert_equal %w(Bar Foo), results.map(&:name)
  end

  def test_custom_select
    order = Order.create!(date: Date.new(2017, 2, 28), amount: 56.72, customer_id: 42)

    results = OccamsRecord.
      query(Order.select('amount, id, date, customer_id').where(customer_id: 42)).run
    assert_equal 1, results.size
    assert_equal({
      amount: 56.72,
      id: order.id,
      date: Date.new(2017, 2, 28),
      customer_id: 42
    }, results[0].to_hash(symbolize_names: true))
  end

  def test_eager_load_custom_select
    results = OccamsRecord.
      query(Order.all).
      eager_load(:line_items, -> { where('1 != 2') }).
      run

    assert_equal LineItem.count, results.map(&:line_items).flatten.size
  end

  def test_belongs_to
    results = OccamsRecord.
      query(Widget.all).
      eager_load(:category).
      run

    assert_equal Widget.all.map { |w|
      "#{w.name}: #{w.category.name}"
    }.sort, results.map { |w|
      "#{w.name}: #{w.category.name}"
    }.sort
  end

  def test_has_one
    results = OccamsRecord.
      query(Widget.all).
      eager_load(:detail).
      run

    assert_equal Widget.all.map { |w|
      "#{w.name}: #{w.detail.text}"
    }.sort, results.map { |w|
      "#{w.name}: #{w.detail.text}"
    }.sort
  end

  def test_has_many
    results = OccamsRecord.
      query(Order.all).
      eager_load(:line_items).
      run

    assert_equal Order.all.map { |o|
      {
        id: o.id,
        date: o.date,
        amount: o.amount,
        customer_id: o.customer_id,
        line_items: o.line_items.map { |i|
          {
            id: i.id,
            order_id: i.order_id,
            item_id: i.item_id,
            item_type: i.item_type,
            amount: i.amount
          }
        }
      }
    }, results.map { |r| r.to_hash(symbolize_names: true) }
  end

  def test_nested
    log = []
    results = OccamsRecord.
      query(Category.all, query_logger: log).
      eager_load(:widgets) {
        eager_load(:detail)
      }.
      run

    assert_equal [
      %q(SELECT "categories".* FROM "categories"),
      %q(SELECT "widgets".* FROM "widgets" WHERE "widgets"."category_id" IN (208889123, 922717355)),
      %q(SELECT "widget_details".* FROM "widget_details" WHERE "widget_details"."widget_id" IN (112844655, 417155790, 683130438, 802847325, 834596858, 919808993)),
    ], log

    assert_equal Category.all.map { |c|
      {
        id: c.id,
        name: c.name,
        widgets: c.widgets.map { |w|
          {
            id: w.id,
            name: w.name,
            category_id: w.category_id,
            detail: {
              id: w.detail.id,
              widget_id: w.detail.widget_id,
              text: w.detail.text
            }
          }
        }
      }
    }, results.map { |r| r.to_hash(symbolize_names: true) }
  end

  def test_nested_with_poly_belongs_to
    log = []
    results = OccamsRecord.
      query(Order.all, query_logger: log).
      eager_load(:customer).
      eager_load(:line_items) {
        eager_load(:item)
      }.
      run

    assert_equal [
      %q(SELECT "orders".* FROM "orders"),
      %q(SELECT "customers".* FROM "customers" WHERE "customers"."id" IN (846114006, 980204181)),
      %q(SELECT "line_items".* FROM "line_items" WHERE "line_items"."order_id" IN (683130438, 834596858)),
      %q(SELECT "widgets".* FROM "widgets" WHERE "widgets"."id" IN (417155790, 112844655, 683130438)),
      %q(SELECT "splines".* FROM "splines" WHERE "splines"."id" IN (683130438, 112844655)),
    ], log

    assert_equal Order.all.map { |o|
      {
        id: o.id,
        date: o.date,
        amount: o.amount,
        customer_id: o.customer_id,
        customer: {
          id: o.customer.id,
          name: o.customer.name
        },
        line_items: o.line_items.map { |i|
          {
            id: i.id,
            order_id: i.order_id,
            item_id: i.item_id,
            item_type: i.item_type,
            amount: i.amount,
            item: {
              id: i.item.id,
              name: i.item.name,
              category_id: i.item.category_id
            }
          }
        }
      }
    }, results.map { |r| r.to_hash(symbolize_names: true) }
  end

  def test_poly_has_many
    results = OccamsRecord.
      query(Widget.all).
      eager_load(:line_items).
      run

    assert_equal Widget.count, results.size
    results.each do |widget|
      assert_equal LineItem.where(item_id: widget.id, item_type: 'Widget').count, widget.line_items.size
    end
  end

  def test_has_and_belongs_to_many
    users = OccamsRecord.
      query(User.all).
      eager_load(:offices).
      run

    assert_equal 3, users.count
    bob = users.detect { |u| u.username == 'bob' }
    sue = users.detect { |u| u.username == 'sue' }
    craig = users.detect { |u| u.username == 'craig' }

    assert_equal %w(Bar Foo), bob.offices.map(&:name).sort
    assert_equal %w(Bar Zorp), sue.offices.map(&:name).sort
    assert_equal %w(Foo), craig.offices.map(&:name).sort
  end

  def test_including_module
    mod_a, mod_b, mod_c = Module.new, Module.new, Module.new
    orders = OccamsRecord.
      query(Order.all, use: mod_a).
      eager_load(:line_items, use: mod_b) {
        eager_load(:item, use: mod_c)
      }.
      run

    assert_equal Order.count, orders.size
    orders.each do |order|
      assert order.is_a?(mod_a)
      assert order.line_items.all? { |line_item| line_item.is_a? mod_b }
      assert order.line_items.all? { |line_item| line_item.item.is_a? mod_c }
    end
  end
end
