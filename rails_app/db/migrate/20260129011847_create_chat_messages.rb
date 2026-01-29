class CreateChatMessages < ActiveRecord::Migration[8.1]
  def change
    create_table :chat_messages do |t|
      t.references :chat_thread, null: false, foreign_key: true
      t.string :role
      t.text :content
      t.string :function_name

      t.timestamps
    end
  end
end
