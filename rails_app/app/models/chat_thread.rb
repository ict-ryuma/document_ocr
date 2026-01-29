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
      case msg.role
      when "system", "user"
        # 通常のメッセージ
        {
          role: msg.role,
          content: msg.content
        }
      when "assistant"
        # アシスタントの応答（tool_callsを含む可能性あり）
        if msg.content.starts_with?("[{")
          # tool_callsのJSON文字列
          {
            role: "assistant",
            content: nil,
            tool_calls: JSON.parse(msg.content)
          }
        else
          # 通常のテキスト応答
          {
            role: "assistant",
            content: msg.content
          }
        end
      when "tool"
        # Function Calling の結果
        {
          role: "tool",
          tool_call_id: msg.function_name,
          content: msg.content
        }
      else
        # その他
        {
          role: msg.role,
          content: msg.content
        }
      end
    end
  end

  private

  def set_default_title
    self.title ||= "新規チャット - #{Time.current.strftime('%Y/%m/%d %H:%M')}"
  end
end
