class CreateSalaryBands < ActiveRecord::Migration[7.1]
  def up
    enable_extension 'btree_gist' unless extension_enabled?('btree_gist')

    create_table :salary_bands do |t|
      t.string     :job_title,         null: false
      t.string     :job_level,         null: false
      t.references :pay_zone,          null: false, foreign_key: true
      t.string     :currency, limit: 3, null: false
      t.bigint     :min_minor_units,   null: false
      t.bigint     :mid_minor_units,   null: false
      t.bigint     :max_minor_units,   null: false
      t.date       :effective_from,    null: false
      t.date       :effective_to
      t.timestamps
    end

    add_index :salary_bands,
              %i[pay_zone_id job_title job_level effective_from],
              order: { effective_from: :desc },
              name: 'index_salary_bands_on_zone_title_level_from'

    execute <<~SQL
      ALTER TABLE salary_bands
      ADD CONSTRAINT salary_bands_no_overlap
      EXCLUDE USING gist (
        pay_zone_id WITH =,
        job_title   WITH =,
        job_level   WITH =,
        daterange(effective_from, effective_to, '[)') WITH &&
      );

      ALTER TABLE salary_bands
      ADD CONSTRAINT salary_bands_ordered CHECK (
        min_minor_units <= mid_minor_units AND mid_minor_units <= max_minor_units
      );
    SQL
  end

  def down
    drop_table :salary_bands
    # btree_gist may be used by other tables; leave extension installed.
  end
end
