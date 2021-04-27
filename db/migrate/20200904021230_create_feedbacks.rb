class CreateFeedbacks < ActiveRecord::Migration[5.2]
  def change
    create_table :feedbacks do |t|
      t.string :rating, null: false
      t.references :resource, index: true, foreign_key: true
      t.references :service, index: true, foreign_key: true

      t.timestamps
    end
  end
end
