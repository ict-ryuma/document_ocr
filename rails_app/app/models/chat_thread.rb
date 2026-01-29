class ChatThread < ApplicationRecord
  has_many :chat_messages, dependent: :destroy

  # User関連付けはオプション（ログインなしでも使える）
  # belongs_to :user, optional: true

  validates :title, presence: true

  # デフォルトタイトルを設定
  after_initialize :set_default_title, if: :new_record?

  # 会話履歴をOpenAI形式の配列に変換
  def conversation_history
    chat_messages.order(:created_at).map do |msg|
      {
        role: msg.role,
        content: msg.content
      }.tap do |hash|
        # tool_call_id がある場合は追加（Function Calling の応答用）
        hash[:tool_call_id] = msg.function_name if msg.role == "tool" && msg.function_name.present?
      end
    end
  end

  private

  def set_default_title
    self.title ||= "新規チャット - #{Time.current.strftime('%Y/%m/%d %H:%M')}"
  end
end
