# -*- coding: utf-8 -*-
require 'sinatra/base'
require 'slim'
require 'json'
require 'mysql2'
require 'net/http'
require 'rack/cache'

if ENV['RACK_ENV'] != 'production'
  require 'pry'
  require "rack-lineprof"
end

module Net
  class HTTP::Purge < HTTPRequest
        METHOD='PURGE'
        REQUEST_HAS_BODY = false
        RESPONSE_HAS_BODY = true
  end
end

class Isucon2App < Sinatra::Base
  $stdout.sync = true if development?
  set :slim, :pretty => true, :layout => true
  set :port, 3000

  use Rack::Cache

  configure do
    #set static_cache_control: [:public, max_age: 60*60]
  end

  if development?
    use Rack::Lineprof, profile: "views/*|app.rb"
  end

  helpers do

    def dict(arg)
      if defined?(@dict)
        @dict[arg.to_i - 1]
      else
        @dict = []
        10.times do |idx|
          variation = [
            {id: 1, name: 'アリーナ席'},
            {id: 2, name: 'スタンド席'},
            {id: 3, name: 'アリーナ席'},
            {id: 4, name: 'スタンド席'},
            {id: 5, name: 'アリーナ席'},
            {id: 6, name: 'スタンド席'},
            {id: 7, name: 'アリーナ席'},
            {id: 8, name: 'スタンド席'},
            {id: 9, name: 'アリーナ席'},
            {id: 10, name: 'スタンド席'},
          ][idx]
          if variation[:id] < 3
            ticket = {id: 1, name: '西武ドームライブ'}
          elsif variation[:id] < 5
            ticket = {id: 2, name: '東京ドームライブ'}
          elsif variation[:id] < 7
            ticket = {id: 3, name: 'さいたまスーパーアリーナライブ'}
          elsif variation[:id] < 9
            ticket = {id: 4, name: '横浜アリーナライブ'}
          elsif variation[:id] < 11
            ticket = {id: 5, name: '西武ドームライブ'}
          end

          if ticket[:id] < 3
            artist = {id: 1, name: 'NHN48'}
          else
            artist = {id: 2, name: 'はだいろクローバーZ'}
          end

          @dict << {
            v_name: variation[:name],
            t_name: ticket[:name],
            a_name: artist[:name],
          }
        end

        return @dict[arg.to_i - 1]
      end
    end

    def development?
      !production?
    end

    def production?
      ENV['RACK_ENV'] == 'production'
    end

    def purge_cache(uri)
      # system("curl -X PURGE -H 'Host: ec2-54-64-183-81.ap-northeast-1.compute.amazonaws.com' '#{uri}' >/dev/null 2>&1")

      uri = uri.is_a?(URI) ? uri : URI.parse(uri)
      Net::HTTP.start(uri.host,uri.port) do |http|
        presp = http.request Net::HTTP::Purge.new uri.request_uri
        $stdout.puts "#{presp.code}: #{presp.message}" if development?
        unless (200...400).include?(presp.code.to_i)
          $stdout.puts "A problem occurred. PURGE was not performed(#{presp.code.to_i}): #{uri.request_uri}"
        else
          $stdout.puts "Cache purged (#{presp.code.to_i}): #{uri.request_uri}" if development?
        end
      end
    end

    def connection
      return @connection if defined?(@connection)

      config = JSON.parse(IO.read(File.dirname(__FILE__) + "/../config/common.#{ ENV['ISUCON_ENV'] || 'local' }.json"))['database']
      @connection = Mysql2::Client.new(
        :host => config['host'],
        :port => config['port'],
        :username => config['username'],
        :password => config['password'],
        :database => config['dbname'],
        :reconnect => true,
      )
    end

    def recent_sold
      mysql = connection
      recent_sold = mysql.query('SELECT seat_id, a_name, t_name, v_name FROM recent_sold ORDER BY order_id DESC LIMIT 10')

      if recent_sold.size > 0
        recent_sold
      else
        update_recent_sold
      end
    end

    def update_recent_sold
      mysql = connection

      recent_sold = mysql.query('SELECT seat_id, variation_id FROM stock ORDER BY order_id DESC LIMIT 10').to_a



      return [] if recent_sold.size == 0

      recent_sold.each do |stock|
        dict(stock['variation_id']).each do |key, value|
          stock[key] = value
        end
      end

      values = recent_sold.map { |data|
        %Q{('#{data["seat_id"]}',#{data["order_id"] ? data["order_id"] : "NULL" },'#{data["a_name"]}','#{data["t_name"]}','#{data["v_name"]}')}
      }.join(",")
      mysql.query(
        "
        INSERT INTO recent_sold (seat_id, order_id, a_name, t_name, v_name)
        VALUES #{values}
        ON DUPLICATE KEY UPDATE
          recent_sold.seat_id=VALUES(seat_id),
          recent_sold.order_id=VALUES(order_id),
          recent_sold.a_name=VALUES(a_name),
          recent_sold.t_name=VALUES(t_name),
          recent_sold.v_name=VALUES(v_name)
        "
      )

      recent_sold
    end

    def initialize_count
      mysql = connection
      tickets = mysql.query("SELECT id FROM ticket")
      tickets.each do |ticket|
        update_ticket_count(ticket['id'])
      end
    end

    def update_ticket_count(ticket_id)
      mysql = connection
      count = ticket_count(ticket_id)
      mysql.query("UPDATE ticket SET count = #{count} WHERE id = #{ticket_id}")
    end

    def decrement_ticket_count(ticket_id)
      mysql = connection
      mysql.query("UPDATE ticket SET count = count - 1 WHERE id = #{ticket_id}")
    end

    def ticket_count(ticket_id)
      mysql = connection
      mysql.query(
        "SELECT COUNT(*) AS cnt FROM variation
         INNER JOIN stock ON stock.variation_id = variation.id
         WHERE variation.ticket_id = #{ ticket_id } AND stock.order_id IS NULL",
      ).first["cnt"]
    end
  end

  # main

  get '/' do
    #cache_control :public, max_age: 600
    mysql = connection
    artists = mysql.query("SELECT * FROM artist ORDER BY id")
    slim :index, :locals => {
      :artists => artists,
    }
  end

  get '/artist/:artistid' do
    #cache_control :public, max_age: 600
    mysql = connection
    artist  = mysql.query(
      "SELECT id, name FROM artist WHERE id = #{ params[:artistid] } LIMIT 1",
    ).first
    tickets = mysql.query(
      "SELECT id, name, count FROM ticket WHERE artist_id = #{ artist['id'] } ORDER BY id",
    )
    slim :artist, :locals => {
      :artist  => artist,
      :tickets => tickets,
    }
  end

  get '/ticket/:ticketid' do
    mysql = connection
    ticket = mysql.query(
      "SELECT t.*, a.name AS artist_name FROM ticket t
       INNER JOIN artist a ON t.artist_id = a.id
       WHERE t.id = #{ params[:ticketid] } LIMIT 1",
    ).first

    variations = mysql.query("SELECT id, name FROM variation WHERE ticket_id = #{ ticket['id'] } ORDER BY id").to_a
    variations.each do |variation|
      variation["count"] = mysql.query("SELECT COUNT(*) AS cnt FROM stock WHERE variation_id = #{ variation['id'] } AND order_id IS NULL").first["cnt"]
      variation["stock"] = {}

      stocks = mysql.query("SELECT seat_id, order_id FROM stock WHERE variation_id = #{ variation['id'] }").to_a
      stocks.each do |stock|
        variation["stock"][stock["seat_id"]] = stock["order_id"]
      end
    end
    slim :ticket, locals: {
      ticket: ticket,
      variations: variations,
    }
  end


  get '/purge_all_cache' do
    purge_cache('http://ec2-54-64-183-81.ap-northeast-1.compute.amazonaws.com/')
    purge_cache("http://ec2-54-64-183-81.ap-northeast-1.compute.amazonaws.com/artist/1")
    purge_cache("http://ec2-54-64-183-81.ap-northeast-1.compute.amazonaws.com/artist/2")
    5.times do |i|
      purge_cache("http://ec2-54-64-183-81.ap-northeast-1.compute.amazonaws.com/ticket/#{i+1}")
    end
    "OK"
  end

  post '/buy' do
    mysql = connection
    mysql.query('BEGIN')
    mysql.query("INSERT INTO order_request (member_id) VALUES ('#{ params[:member_id] }')")
    order_id = mysql.last_id
    mysql.query(
      "UPDATE stock SET order_id = #{ order_id }
       WHERE variation_id = #{ params[:variation_id] } AND order_id IS NULL
       ORDER BY RAND() LIMIT 1",
    )


    if mysql.affected_rows > 0
      update_recent_sold

      seat_id = mysql.query(
        "SELECT seat_id FROM stock WHERE order_id = #{ order_id } LIMIT 1",
      ).first['seat_id']
      mysql.query('COMMIT')

      ticket_id = mysql.query(
        "SELECT ticket_id FROM variation WHERE id = #{ mysql.escape(params[:variation_id]) } LIMIT 1",
      ).first['ticket_id']

      decrement_ticket_count(ticket_id)

      slim :complete, :locals => { :seat_id => seat_id, :member_id => params[:member_id] }
    else
      mysql.query('ROLLBACK')
      slim :soldout
    end
  end

  # admin

  get '/admin' do
    #cache_control :public, max_age: 600
    slim :admin
  end

  get '/admin/order.csv' do
    #cache_control :public, max_age: 600
    mysql = connection
    body  = ''
    orders = mysql.query(
      'SELECT order_request.*, stock.seat_id, stock.variation_id, stock.updated_at
       FROM order_request JOIN stock ON order_request.id = stock.order_id
       ORDER BY order_request.id ASC',
    )
    orders.each do |order|
      order['updated_at'] = order['updated_at'].strftime('%Y-%m-%d %X')
      body += order.values_at('id', 'member_id', 'seat_id', 'variation_id', 'updated_at').join(',')
      body += "\n"
    end
    [200, { 'Content-Type' => 'text/csv' }, body]
  end

  post '/admin' do
    mysql = connection
    open(File.dirname(__FILE__) + '/../config/database/initial_data.sql') do |file|
      file.each do |line|
        next unless line.strip!.length > 0
        mysql.query(line)
      end
    end
    initialize_count
    update_recent_sold

    purge_cache('http://ec2-54-64-183-81.ap-northeast-1.compute.amazonaws.com/')
    5.times do |i|
      purge_cache("http://ec2-54-64-183-81.ap-northeast-1.compute.amazonaws.com/ticket/#{i+1}")
    end

    redirect '/admin', 302
  end

  run! if app_file == $0
end
