class CreateChatThreads < ActiveRecord::Migration[8.1]
  def change
    create_table :chat_threads do |t|
      t.string :title
      t.integer :user_id

      t.timestamps
    end
  end
end
