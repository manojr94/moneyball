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

ActiveRecord::Schema[7.1].define(version: 2024_01_01_000007) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  # Custom types defined in this database.
  # Note that some types may not work with other database engines. Be careful if changing database.
  create_enum "employee_status", ["active", "inactive", "terminated"]
  create_enum "region_type", ["na", "latam", "emea", "apac"]

  create_table "countries", primary_key: "code", id: :string, force: :cascade do |t|
    t.string "name"
    t.string "default_currency", limit: 3
    t.bigint "pay_zone_id"
    t.enum "region", enum_type: "region_type"
    t.boolean "needs_review", default: false, null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.index ["pay_zone_id"], name: "index_countries_on_pay_zone_id"
  end

  create_table "departments", force: :cascade do |t|
    t.string "name", null: false
    t.string "slug", null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.index ["name"], name: "index_departments_on_name", unique: true
    t.index ["slug"], name: "index_departments_on_slug", unique: true
  end

  create_table "employees", force: :cascade do |t|
    t.string "employee_number", null: false
    t.string "first_name", null: false
    t.string "last_name", null: false
    t.string "email", null: false
    t.string "country_code", limit: 2, null: false
    t.bigint "department_id", null: false
    t.string "job_title", null: false
    t.string "job_level", null: false
    t.date "hire_date", null: false
    t.enum "status", default: "active", null: false, enum_type: "employee_status"
    t.date "terminated_on"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.index ["country_code"], name: "index_employees_on_country_code"
    t.index ["department_id"], name: "index_employees_on_department_id"
    t.index ["email"], name: "index_employees_on_email", unique: true
    t.index ["employee_number"], name: "index_employees_on_employee_number", unique: true
    t.index ["status"], name: "index_employees_on_active_status", where: "(status = 'active'::employee_status)"
  end

  create_table "exchange_rates", force: :cascade do |t|
    t.string "currency", limit: 3, null: false
    t.decimal "rate_to_usd", precision: 18, scale: 8, null: false
    t.date "effective_date", null: false
    t.datetime "created_at", null: false
    t.index ["currency", "effective_date"], name: "index_exchange_rates_on_currency_and_effective_date", unique: true, order: { effective_date: :desc }
  end

  create_table "pay_zones", force: :cascade do |t|
    t.string "name", null: false
    t.string "slug", null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.index ["name"], name: "index_pay_zones_on_name", unique: true
    t.index ["slug"], name: "index_pay_zones_on_slug", unique: true
  end

  create_table "salaries", force: :cascade do |t|
    t.bigint "employee_id", null: false
    t.bigint "amount_minor_units", null: false
    t.string "currency", limit: 3, null: false
    t.date "effective_date", null: false
    t.string "reason", null: false
    t.bigint "created_by_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["employee_id", "effective_date"], name: "index_salaries_on_employee_id_and_effective_date", order: { effective_date: :desc }
    t.index ["employee_id"], name: "index_salaries_on_employee_id"
  end

  add_foreign_key "countries", "pay_zones"
  add_foreign_key "employees", "countries", column: "country_code", primary_key: "code"
  add_foreign_key "employees", "departments"
  add_foreign_key "salaries", "employees"
end
