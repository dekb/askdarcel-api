class CreateReviews < ActiveRecord::Migration[5.2]
  def change
    create_table :reviews do |t|
      t.text :review
      t.text :tags, array: true, default: []
      t.references :feedback, index: true, foreign_key: true

      t.timestamps
    end
  end
end
