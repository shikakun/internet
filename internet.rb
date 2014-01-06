# coding: utf-8
require 'securerandom'

Dotenv.load
Sequel::Model.plugin(:schema)

db = {
  user:     ENV['USER'],
  dbname:   ENV['DBNAME'],
  password: ENV['PASSWORD'],
  host:     ENV['HOST']
}

configure :development do
  DB = Sequel.connect("sqlite://db/#{settings.environment}.db")
end

configure :production do
  DB = Sequel.connect("mysql2://#{db[:user]}:#{db[:password]}@#{db[:host]}/#{db[:dbname]}")
end

class Checkins < Sequel::Model
  unless table_exists?
    set_schema do
      primary_key :id
      String :uid
      String :nickname
      String :image
      String :token
      String :secret
      String :address
    end
    create_table
  end
end

use Rack::Session::Cookie,
  :key => 'rack.session',
  :path => '/',
  :expire_after => 3600,
  :secret => ENV['SESSION_SECRET']

use OmniAuth::Builder do
  provider :twitter, ENV['TWITTER_CONSUMER_KEY'], ENV['TWITTER_CONSUMER_SECRET']
end

before do
  Twitter.configure do |config|
    config.consumer_key       = ENV['TWITTER_CONSUMER_KEY']
    config.consumer_secret    = ENV['TWITTER_CONSUMER_SECRET']
    config.oauth_token        = session['token']
    config.oauth_token_secret = session['secret']
  end
end

def tweet(tweets)
  if settings.environment == :production
    twitter_client = Twitter::Client.new
    twitter_client.update(tweets)
  elsif settings.environment == :development
    flash.next[:info] = tweets
  end
end

def ikachan(tweets)
  return false if ENV['IKACHAN_PATH'].nil? || ENV['IKACHAN_PATH'].empty?
  ikachan_url = ENV['IKACHAN_PATH']
  ikachan_client = HTTPClient.new()
  puts ikachan_client.post_content(ikachan_url,'channel' => "#internet",'message' => tweets)
end

not_found do
  redirect "/" + URI.escape("404")
end

error do
  redirect "/auth/twitter"
end

get "/" do
  redirect "/%e6%b8%8b%e8%b0%b7"
end

get "/:address" do
  if @params[:address] == "サイトマップ"
    sites = Array.new
    Checkins.each { |r|
      sites << r.address
    }
    @sitemaps = sites.group_by{|e| e}.sort_by{|_,v|-v.size}.map(&:first)
    slim :sitemap
  elsif @params[:address] == "最近のチェックイン"
    @recents = Checkins.limit(50).order_by(Sequel.desc(:id))
    slim :recent
  else
    visitors = Array.new
    Checkins.filter(address: @params[:address]).order_by(Sequel.desc(:id)).each { |r|
      visitors << r.nickname
    }
    visitors = visitors.group_by{|e| e}.sort_by{|_,v|-v.size}.map(&:first)
    @mayor = visitors[0]

    keyword = SimpleRSS.parse open('http://d.hatena.ne.jp/keyword?mode=rss&ie=utf8&word=' + URI.escape(@params[:address]))
    descriptions = Array.new
    keyword.items.each { |r|
      descriptions << r.description
    }
    if descriptions[0] && /。/ =~ descriptions[0].force_encoding('UTF-8')
      @detail = descriptions[0].force_encoding('UTF-8').split('。').first
    end

    @button = request.url.gsub(/http:/, '') + '/button'
    session['csrf_token'] = SecureRandom.base64

    @checkins = Checkins.filter(address: @params[:address]).order_by(Sequel.desc(:id))
    slim :index
  end
end

get "/:address/button" do
  content_type :txt
  <<-JAVASCRIPT
document.write("<input type=\\"button\\" value=\\"チェックイン\\" onclick=\\"location.href='http://#{request.host}/#{@params[:address]}/checkin'\\">");
  JAVASCRIPT
end

before "/:address/checkin" do
  if @params[:csrf_token] != session['csrf_token']
    flash[:alert] = 'csrf token is invalid'
    redirect "/#{URI.escape(@params[:address])}"
  end
  twitter_clinet = Twitter::Client.new
  begin
    twitter_clinet.verify_credentials
  rescue
    session['address'] = @params[:address]
    redirect "/auth/twitter"
  end
end

post "/:address/checkin" do
  Checkins.create(
    :uid => session['uid'],
    :nickname => session['nickname'],
    :image => session['image'],
    :token => session['token'],
    :secret => session['secret'],
    :address => session['address']
  )
  tweet(session['address'] + "にいます http://t.heinter.net/" + URI.escape(session['address']))
  ikachan(session['nickname'] + " が " + session['address'] + " にいます")
  redirect "/#{URI.escape(@params[:address])}"
end

get "/auth/:provider/callback" do
  auth = request.env["omniauth.auth"]
  session['uid'] = auth['uid']
  session['nickname'] = auth['info']['nickname']
  session['image'] = auth['info']['image']
  session['token'] = auth['credentials']['token']
  session['secret'] = auth['credentials']['secret']
  redirect "/" + URI.escape(session['address'])
end
