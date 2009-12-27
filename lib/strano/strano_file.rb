require 'active_support'
require 'action_view'

class StranoFile
  include ActionView::Helpers::NumberHelper
  include ActionView::Helpers::DateHelper 

  include Strano::Term

  NUM_COLS = 80

  attr_accessor :name, :total_size, :start_time, :header_has_been_output, :received

  def initialize
    @received = 0
    @start_time = Time.now
    @header_has_been_output = false
  end

  def update(options = {})
    @total_size = options[:total_size]
    @name = options[:name]
    @received = options[:received]
  end

  def status_message
    width = ((NUM_COLS.to_f / 100.to_f) * percentage.to_f).floor
    "#{color(:blue)}[#{color(:green)}" + (("=" * width) + ">").ljust(NUM_COLS + 1) + "#{color(:blue)}] #{color(:yellow)}#{number_to_human_size(received).ljust(8)} | " + (percentage + '%').rjust(6) + (" | #{number_to_human_size(average_bytes_per_second)}/s").ljust(14)
  end

  def time_message
    return '' unless realistic_time_estimate?
    from_time = Time.now
    (" | " + distance_of_time_in_words(from_time, from_time + est_seconds_left, true) + " left")
  end

  def header_message
    return '' if @header_has_been_output
    @header_has_been_output = true
    "\n #{color(:green)}#{name.ljust(NUM_COLS)}   #{color(:yellow)}#{number_to_human_size(total_size)}#{color(:none)}\n\n\n"
  end

  def full_message
    message = ""
    message += header_message
    message += "\e[1A\e[2K"
    message += status_message
    message += time_message
    message += color(:none)
  end

  def completed_message
    " #{color(:green)}Done - took %.2f minutes#{color(:none)}\n" % ((Time.now - start_time).to_f / 60.0)
  end

  protected
    def realistic_time_estimate?
      (Time.now - start_time) > 2 && received > 0
    end

    def est_seconds_left
      (total_size - received) / average_bytes_per_second
    end

    def average_bytes_per_second
      (received.to_f / (Time.now - start_time).to_f)
    end

    def percentage
      "%.2f" % ((received.to_f / total_size.to_f) * 100)
    end
end
