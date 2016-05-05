#coding: UTF-8

Plugin.create(:"mikutter-find-tl") {

  # インクリメンタルサーチ用のクラス
  class IncrementalSearch
    attr_accessor :word

    # スレッド停止
    def stop
      @stop = true
    end

    def initialize(model, &searched)
      @word = ""

      # スレッドを起こす
      Thread.new {
        prev_word = ""

        loop {
          # スレッド停止
          if @stop
            changed_messages = []

            model.each { |_|
              message = _[2][Gtk::TimeLine::InnerTL::MESSAGE]

              if message[:search_match] != nil
                message[:search_match] = nil
                changed_messages << message
              end
            }

            if changed_messages.count > 0
              Delayer.new {
                searched.(changed_messages)
              }
            end

            break
          end

          # 検索ワードが変わった
          if prev_word != @word
            # メッセージにキーワードに一致してるかを示す:serach_matchをつける
            messages = []
            model.each { |_| messages << _[2][Gtk::TimeLine::InnerTL::MESSAGE] }

            changed_messages = []

            messages.each { |message|
              message[:search_match] ||= false

              match = ((@word != "") && message.to_s.include?(@word))

              if message[:search_match] != match
                changed_messages << message
              end

              message[:search_match] = match
            }

            if changed_messages.count > 0
              Delayer.new {
                searched.(changed_messages)
              }
            end
          end

          prev_word = @word

          sleep(0.5)
        }
      }
    end
  end

  # 検索ボックスを作る
  def generate_findbox
    box = Gtk::HBox.new

    box.instance_eval {
      @close_button = Gtk::Button.new.add(Gtk::WebIcon.new(Skin.get("close.png"), 16, 16))
      @find_entry = Gtk::Entry.new

      self.pack_start(@close_button, false)
      self.pack_start(Gtk::Label.new(Plugin._("TL内検索")), false, true, 1)
      self.pack_start(@find_entry)

      def close_button
        @close_button
      end

      def find_entry
        @find_entry
      end
    }

    box.show_all

    box
  end

  # 検索結果の背景色を変更する
  filter_message_background_color { |message, color|
    selected = message.is_a?(Gdk::MiraclePainter) && message.selected

    new_color = if !selected && message.message[:search_match]
      [65535, 32767, 32767]
    else
      color
    end

    [message, new_color]
  }

  # 検索ボックスを閉じる
  def close_findbox!
    if @shown
      @shown[:incremental_search].stop 
      @shown[:tab_container].remove(@shown[:findbox])
      @shown = nil
    end
  end

  # コマンド
  command(:find,
    :name => _("TL検索"),
    :condition => lambda { |opt| true },
    :visible => true,
    :role => :timeline) { |opt|

    # 検索ボックス表示中
    if @shown
      if @shown[:tl] == opt.widget.slug
        # 検索ボックスにフォーカスを移動
        @shown[opt.widget.slug].find_entry.grab_focus
        next
      else
        close_findbox!
      end
    end

    widget = Plugin[:gtk].widgetof(opt.widget)

    # 検索結果が優先されるようにTLの並び順を変更
    widget.tl.set_order { |message|
      x = if message[:search_match]
        # 1年後に更新されたことにする
        message.modified.to_i + (60 * 60 * 24 * 365)
      else
        message.modified.to_i
      end
    }

    # ウィジェットの構築
    tab_container = widget.parent
    findbox = generate_findbox
    tab_container.pack_start(findbox, false)
    tab_container.reorder_child(findbox, 1)

    # 検索ボックスにフォーカスを移動
    findbox.find_entry.grab_focus

    # 検索スレッドを起こす
    incremental_search = IncrementalSearch.new(widget.tl.model) { |changed_messages|
      # メッセージを更新する
      changed_messages.each { |message| widget.modified(message) }
    }

    # 表示中の検索ボックスの情報を記憶する
    @shown = {
      :tl => [opt.widget.slug],
      :findbox => findbox,
      :incremental_search => incremental_search,
      :tab_container => tab_container
    }

    # 閉じるボタン
    findbox.close_button.ssc(:clicked) { |w|
      close_findbox!
    }
 
    # 検索ボックスの文字列が変化した
    findbox.find_entry.ssc(:changed) { |w|
      incremental_search.word = w.text
    }
  }
}


