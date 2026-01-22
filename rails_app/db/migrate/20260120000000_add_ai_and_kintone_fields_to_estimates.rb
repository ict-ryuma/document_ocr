class AddAiAndKintoneFieldsToEstimates < ActiveRecord::Migration[8.0]
  def change
    add_column :estimates, :ai_analysis, :text, comment: 'Azure OpenAI分析結果（JSON形式）'
    add_column :estimates, :kintone_record_id, :string, comment: 'kintoneレコードID'

    add_index :estimates, :kintone_record_id
  end
end
