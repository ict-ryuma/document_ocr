class ChatMessage < ApplicationRecord
  belongs_to :chat_thread

  validates :role, presence: true, inclusion: { in: %w[system user assistant tool function] }
  validates :content, presence: true

  # OpenAI形式のハッシュに変換
  def to_openai_format
    {
      role: role,
      content: content
    }.tap do |hash|
      # tool_call_id がある場合は追加（Function Calling の応答用）
      hash[:tool_call_id] = function_name if role == "tool" && function_name.present?
    end
  end
end
