require "./src/helpers/*"  

require "kemal"
require "kemal-session"
require "http/client"
require "mysql"
require "./src/view_helpers" # make accessible to all views

Session.config do |config|
  config.secret = File.read("./db/local_cookie_secret") # generate like crystal eval 'require "secure_random"; puts SecureRandom.hex(64)' > local_cookie_secret
  config.gc_interval = 1.days
  config.timeout = Time::Span.new(days: 30, hours: 0, minutes: 0, seconds: 0)
  config.engine = Session::FileEngine.new({:sessions_dir => "./sessions/"}) # file based to survive restarts, mainly :|
  config.secure = true # send "secure only" cookies
end

before_all do |env|
  env.response.headers.add "Access-Control-Allow-Origin", "*" # apparently has to have this for "amazon.com" to request something from my site. Weird browsers...
end

class CustomHandler < Kemal::Handler # don't know how to interrupt it from a before_all :|
  def call(env)
    if (env.request.path =~ /delete|nuke|personalized/ || env.request.method == "POST") && !logged_in?(env) && !is_dev?
      if env.request.method == "GET"
        env.session.string("redirect_to_after_login", "#{env.request.path}?#{env.request.query}") 
      end # else too hard
      add_to_flash env, "Thanks for contributing to our site! Please login to unleash its full awesomeness, first, here:"
      env.redirect "/login" 
    elsif env.request.host !~ /localhost|playitmyway/
      # sometimes some crawlers were calling https://freeldssheetmusic.org as if it were this, weird
      raise "wrong host #{env.request.host}" 
    else
      call_next env
    end
  end
end

add_handler CustomHandler.new

# https://github.com/crystal-lang/crystal/issues/3997 crystal doesn't effectively call GC full whaat? 
spawn do
  loop do
    sleep 0.5
    GC.collect
  end
end

def standardize_url(unescaped)
  original = unescaped
  # basically do it all here, except canonicalize, which we do in javascript...
  if unescaped =~ /amazon.com|netflix.com/
    unescaped = unescaped.split("?")[0] # strip off extra cruft but google play needs to keep it https://play.google.com/store/movies/details/Ice_Age_Dawn_of_the_Dinosaurs?id=FkVpRvzYblc
  end
  unescaped = unescaped.split("&")[0] # strip off cruft https://www.youtube.com/watch?v=FzT9MS3n83U&list=PL7326EF82122776A9&ndex=21 :|
  unescaped = unescaped.gsub("smile.amazon", "www.amazon") # standardize to always www
  unescaped = unescaped.split("#")[0] # trailing #, die!
  unescaped
end

def db_style_from_query_url(env)
  real_url = env.params.query["url"] # already unescaped it on its way in, kind of them..
  sanitize_html standardize_url(real_url)
end

get "/ping" do |env|
  "yes"
end

get "/redo_all_thumbnails" do |env|
  Url.all.each &.create_thumbnail
  "did 'em"
end

get "/sync_web_server" do |env|
  Kemal.stop # AFAICT only stops accepting new...
  spawn do
    sleep 0.1 # faux quiesce LOL
    system("~/sync.sh") # kills this process XXXX even more graceful restart...hrm...
  end
  "from server: restarting it in 0.1..." 
end

get "/all_tags" do |env|
  Tag.all.inspect
end

get "/for_current_just_settings_json" do |env|
  sanitized_url = db_style_from_query_url(env)
  episode_number = env.params.query["episode_number"].to_i # should always be present :)
  # this one looks up by URL and episode number
  url_or_nil = Url.get_only_or_nil_by_url_and_episode_number(sanitized_url, episode_number)
  if !url_or_nil
    env.response.status_code = 412 # avoid kemal default 404 handler :| 412 => precondition failed LOL
    "none for this movie yet #{sanitized_url} #{episode_number}" # not sure if json or javascript LOL
  else
    url = url_or_nil.as(Url)
    env.response.content_type = "application/javascript" # not that this matters nor is useful since no SSL yet :|
    url.count_downloads += 1
    url.save # :| XXX too slow?
    json_for(url, env)
  end
end

def json_for(db_url, env)
  render "views/html5_edited.just_settings.json.ecr"
end

get "/instructions_create_new_url" do | env|
  render "views/instructions_create_new_url.ecr", "views/layout.ecr"
end

get "/delete_all_tags/:url_id" do |env|
  hard_nuke_url_or_nil(env, just_delete_tags: true)
end

get "/nuke_url/:url_id" do |env| # nb: never link to this to let normal users use it [?]
  hard_nuke_url_or_nil(env)
end

get "/nuke_test_by_url" do |env|
  real_url = env.params.query["url"]
  raise("cannot nuke non test movies, please ask us if you want to delete a different movie") unless real_url.includes?("test_movie") # LOL
  sanitized_url = db_style_from_query_url(env)
  url = Url.get_only_or_nil_by_url_and_episode_number(sanitized_url, 0)
  hard_nuke_url_or_nil(env)
end

def hard_nuke_url_or_nil(env, just_delete_tags = false)
  url = get_url_from_url_id(env)
  if url
    save_local_javascript [url], "about to nuke somehow...", env
    url.tag_edit_lists_all_users.each{|tag_edit_list|
      tag_edit_list.destroy_tag_edit_list_to_tags
      tag_edit_list.destroy_no_cascade
    }
    url.tags.each &.destroy_no_cascade # already nuked its edit lists bindings
    return "deleted tags" if just_delete_tags
    url.delete_local_image_if_present_no_save
    url.destroy_no_cascade
    "nuked testmovie #{HTML.escape url.inspect} from db, you can start over and re-add it now, to do some more test editing on a blank/clean slate"
  else
   raise "not found to nuke? #{url}"
  end
end

def logged_in?(env)
  env.session.object?("user") || is_dev?
end

get "/delete_tag/:tag_id" do |env|
  id = env.params.url["tag_id"]
  tag = Tag.get_only_by_id(id)
  tag.destroy_in_tag_edit_lists
  tag.destroy_no_cascade
  save_local_javascript [tag.url], "removed #{tag.inspect}", env
  add_to_flash env, "deleted one tag"
  env.redirect "/view_url/#{tag.url.id}"
end

get "/edit_tag/:tag_id" do |env|
  tag = Tag.get_only_by_id(env.params.url["tag_id"])
  url = tag.url
  render "views/edit_tag.ecr", "views/layout.ecr"
end

def get_url_from_url_id(env)
  Url.get_only_by_id(env.params.url["url_id"])
end

get "/new_empty_tag/:url_id" do |env|
  url = get_url_from_url_id(env)
  tag = Tag.new url
  # non zero anyway :|
  tag.start = 1.0
  tag.endy = url.total_time
  add_to_flash env, "this tag is not yet saved, hit the save button when you are done"
  render "views/edit_tag.ecr", "views/layout.ecr"
end

# leave in until all installed extensions updated...whenever that is?
get "/add_tag_from_plugin/:url_id" do |env|
  url = get_url_from_url_id(env)
  tag = Tag.new url
  query = env.params.query
  tag.start = url.human_to_seconds query["start"]
  tag.endy = url.human_to_seconds query["endy"]
  tag.default_action = resanitize_html(query["default_action"])
  # immediate save so that I can rely on repolling this from the UI to get the ID's etc. in a few seconds after submitting it :|
  tag.category = "unknown"
  tag.subcategory = ""
  tag.save
  add_to_flash env, "success! content tag created, please fill in details about it..."
  spawn do
    save_local_javascript [url], tag.inspect, env
  end
  env.redirect "/edit_tag/#{tag.id}"
end

post "/save_tag/:url_id" do |env|
  params = env.params.body
  puts "save tag params #{params}" # to see image url etc.
  is_update = params["id"]?
  if is_update
    tag = Tag.get_only_by_id(params["id"])
  else
    tag = Tag.new(get_url_from_url_id(env))
  end
  url = tag.url
  start = params["start"].strip
  endy = params["endy"].strip
  tag.start = url.human_to_seconds start
  tag.endy = url.human_to_seconds endy
  # somewhat duplicated in javascript :|
  raise "start can't be zero, use 0.1s if you want something start at the beginning" if tag.start == 0
  raise "start is after or equal to end? please use browser back button to correct..." if (tag.start >= tag.endy) # before_save filter LOL
  raise "tag is more than 15 minutes long? This should not typically be expected?" if tag.endy - tag.start > 60*15
  if url.total_time > 0
    if tag.duration > url.total_time - 1
      raise "attempted to save a tag that is the entire length of the movie'ish? that should not be expected?"
    end
  end
  if tag.endy > url.total_time
    raise "tag goes past end of movie?"
  end
  raise "got some timestamp negative?" if tag.start < 0 || tag.endy < 0 # should be impossible :|
  tag.default_action = resanitize_html(params["default_action"])
  tag.category = resanitize_html params["category"]
  if !params["subcategory"].present? # the default [meaning none] is an empty string
    raise "no subcategory selected, please hit back arrow in your browser and select subcategory for tag, if nothing fits then select '... -- other'"
  end
  tag.subcategory = resanitize_html params["subcategory"]
  tag.details = resanitize_html params["details"]
  tag.age_maybe_ok = params["age_maybe_ok"].to_i # default is 0
  if tag.category.in?(["violence", "suspense"]) && tag.age_maybe_ok == 0
    raise "for violence or suspense tags, please also select a value in the age_maybe_ok dropdown, use your browser back button (hit it several times) to try submitting again"
  end
  tag.save
  if (tag2 = tag.overlaps_any? url.tags)
    add_to_flash(env, "appears this tag might accidentally have an overlap with a different tag that starts at #{seconds_to_human tag2.start} and ends at #{seconds_to_human tag2.endy} please make sure this is expected.")
  end
  save_local_javascript [url], tag.inspect, env
  if is_update
    add_to_flash(env, "Success! saved tag at #{seconds_to_human tag.start}, recommend clicking reload tags or doing a browser refresh...")
  else
    add_to_flash(env, "Success! created tag at #{seconds_to_human tag.start}, you can tweak details and/or close this browser tab now.")
end
  env.redirect "/edit_tag/#{tag.id}" # so they can add details...
end

get "/edit_url/:url_id" do |env|
  url = get_url_from_url_id(env)
  render "views/edit_url.ecr", "views/layout.ecr"
end

get "/mass_upload_from_subtitle_file/:url_id" do |env|
  url = get_url_from_url_id(env)
  render "views/mass_upload_from_subtitle_file.ecr", "views/layout.ecr"
end

get "/add_new_tag/:url_id" do |env|
  url = get_url_from_url_id(env)
  render "views/add_new_tag.ecr", "views/layout.ecr"
end

get "/view_url/:url_id" do |env|
  url = get_url_from_url_id(env)
  show_tag_details =  env.params.query["show_tag_details"]?
  render "views/view_url.ecr", "views/layout.ecr"
end

get "/login_from_facebook" do |env|
  access_token = env.params.query["access_token"]
  # get app token
  app_login = JSON.parse download("https://graph.facebook.com/v2.8/oauth/access_token?client_id=187254001787158&client_secret=#{File.read("facebook_app_secret").strip}&grant_type=client_credentials")
  app_token = app_login["access_token"]
  token_info = JSON.parse download("https://graph.facebook.com/v2.8/debug_token?input_token=#{access_token}&access_token=#{app_token}")
  raise "token not for this app?" unless token_info["data"]["app_id"] == "187254001787158" # shouldn't be necessary since the download should have failed with a 400 already, but just in case...
  # we can trust it...
  details = JSON.parse download("https://graph.facebook.com/v2.8/me?fields=email,name&access_token=#{access_token}") # public_profile, user_friends also available, though not through /me [?]
  # {"email" => "rogerpack2005@gmail.com", "name" => "Roger Pack", "id" => "10155234916333140"}
  setup_user_and_session(details["id"].as_s, details["name"].as_s, details["email"].as_s, "facebook", env)
end

get "/login_from_amazon" do |env| # amazon changes the url to this with some GET params after successful auth
  out = JSON.parse download("https://api.amazon.com/auth/o2/tokeninfo?access_token=#{env.params.query["access_token"]}")
  raise "access token does not belong to us?" unless out["aud"] == "amzn1.application-oa2-client.faf94452d819408f83ce8a93e4f46ec6"
  details = JSON.parse download("https://api.amazon.com/user/profile", HTTP::Headers{"Authorization" => "bearer " + env.params.query["access_token"]})
  # {"user_id":"amzn1.account.cwYYXX","name":"Roger Pack","email":"rogerpack2005@gmail.com"}
  setup_user_and_session(details["user_id"].as_s, details["name"].as_s, details["email"].as_s, "amazon", env) # XX don't even need to specify amazon since the user id's are different and we use that today...FWIW.
end

def setup_user_and_session(user_id, name, email, type, env)
  user = User.from_or_new_db(user_id, name, email, type)
  env.session.object("user", user) # not sure if saving it to the session is better or worse than looking it up from the DB every request...
  add_to_flash(env, "Successfully logged in, welcome #{user.name}!")
  if env.session.string?("redirect_to_after_login") 
    env.redirect env.session.string("redirect_to_after_login")
    env.session.delete_string("redirect_to_after_login")
  else
    add_to_flash(env, "Please use your browser's back button (hit it several times) to repost the information you attempted to enter earlier");
    env.redirect "/"
  end
end

get "/logout" do |env|
  render "views/logout.ecr", "views/layout.ecr" 
end

get "/logout_session" do |env| # j.s. sends us here...
  add_to_flash(env, "You have been logged out, thanks!")
  env.session.delete_object("user") # whether there or not :)
  env.redirect "/login" # amazon says to show login page after
end

def download(raw_url, headers = nil)
  begin
    response = HTTP::Client.get raw_url, headers
    response.body
  rescue ex
    raise "unable to download that url=" + raw_url + " #{ex}" # expect url to work :|
  end
end

def get_title_and_sanitized_standardized_canonical_url(real_url)
  real_url = standardize_url(real_url) # put after so the error message is friendlier :)
  downloaded = download(real_url)
  if downloaded =~ /<title[^>]*>(.*)<\/title>/i
    title = $1.strip
  else
    title = "please enter title here" # hopefully never get here :|
  end
  # startlingly, canonical from /gp/ sometimes => /gp/ yikes
  if downloaded =~ /<link rel="canonical" href="([^"]+)"/i
    # https://smile.amazon.com/gp/product/B001J6Y03C did canonical to https://smile.amazon.com/Avatar-Last-Airbender-Season-3/dp/B0190R77GS
    # however https://smile.amazon.com/gp/product/B001J6GZXK -> /dp/B001J6GZXK gah!
    # but still some improvement FWIW :|
    puts "using canonical from url #{$1}"
    real_url = $1
  end
  if real_url.includes?("amazon.com") && real_url.includes?("/gp/") # gp is old, dp is new, we only want dp ever 
    # we should never get here now FWIW, since it converts to /dp/ with canonical above
    raise "appears you're using an amazon web page that is an old style like /gp/ if this is a new movie, please search in amazon for it again, and you should find a url like /dp/, and use that
           if it is an existing movie, enter it as the amazon_second_url instead of main url"
  end
  [title, sanitize_html(real_url)]
end

class String
  def present?
    size > 0
  end
end

get "/new_url_from_plugin" do |env| # add_url add_new
  real_url = env.params.query["url"]
  incoming = env.params.query
  episode_number = incoming["episode_number"].to_i
  episode_name = incoming["episode_name"]
  title = incoming["title"]
  duration = incoming["duration"].to_f
  if real_url =~ /youtube.com/ && !real_url.includes?("?v=")
    raise "youtube nonstandard url detected, please report #{real_url}" # reject https://www.youtube.com/user/paulsoaresjr etc. which are screwy today :| though js does this too...
  end
  create_new_and_redir(real_url, episode_number, episode_name, title, duration, env)
end

get "/new_manual_url" do |env|
  real_url = env.params.query["url"]
  if env.params.query["episode_number"]?
    episode_number = env.params.query["episode_number"].to_i
  else
    episode_number = 0
  end
  create_new_and_redir(real_url, episode_number, "", "", 0.0, env)
end

def create_new_and_redir(real_url, episode_number, episode_name, title, duration, env)
  title_incoming, sanitized_url = get_title_and_sanitized_standardized_canonical_url real_url
  if title == ""
    title = title_incoming
  end
  puts "using sanitized_url=#{sanitized_url} real_url=#{real_url}"
  url_or_nil = Url.get_only_or_nil_by_url_and_episode_number(sanitized_url, episode_number)
  if url_or_nil
    add_to_flash(env, "a movie with that description already exists, editing that instead...")
    env.redirect "/edit_url/#{url_or_nil.id}"
  else
    # a new one
    # cleanup various title crufts
    title = HTML.unescape(title) # &amp => & and there are some :|
    title = title.gsub("&nbsp;", " ") # HTML.unescape doesn't :|
    title = title.gsub(" | Netflix", "");
    title = title.gsub(" - Movies & TV on Google Play", "")
    title = title.gsub(": Amazon   Digital Services LLC", "")
    title = title.gsub("Amazon.com: ", "")
    title = title.gsub(" - YouTube", "")
    if sanitized_url =~ /disneymoviesanywhere/
      title = title.gsub(/^Watch /, "") # prefix :|
      title = title.gsub(" | Disney Movies Anywhere", "")
    end
    title = title.strip
    title = sanitize_html title
    if sanitized_url.includes?("amazon.com") && title.includes?(":")
      title = title.split(":")[0].strip # begone actors
    end
    already_by_name = Url.get_only_or_nil_by_name_and_episode_number(title, episode_number) # don't just blow up on DB constraint :|
    if already_by_name
      return "appears we already have a movie by that title in our database, go to <a href=/view_url/#{already_by_name.id}>here</a> and if it's an exact match, add url #{sanitized_url} as its 'second' amazon url, or report this message to us, we'll fix it"
    end
    url = Url.new
    url.name = title
    url.url = sanitized_url
    url.episode_name = episode_name
    url.episode_number = episode_number
    url.editing_status = "Just started, tags might not be fully complete yet"
    url.total_time = duration
    url.save 
    add_to_flash(env, "Successfully added #{url.name} to our system! Please add some details, then go back and add some content tags for it!")
    download_youtube_image_if_none url
    env.redirect "/edit_url/#{url.id}"
  end
end

def sanitize_html(name)
  HTML.escape name
end

def get_all_urls_except_just_started
  urls = Url.all_except_just_started
  put_test_last(urls)
end

def get_all_urls
  urls = Url.all
  put_test_last(urls)
end

def put_test_last(urls)
  if urls[0].human_readable_company == "inet2"
    urls.push urls.shift # put it last :|
  end
  urls
end

get "/" do |env| # index home
  all_urls = get_all_urls
  all_urls_except_just_started = all_urls.reject{|url| url.editing_status == "Just started, tags might not be fully complete yet"}
  all_urls_just_started = all_urls.select{|url| url.editing_status == "Just started, tags might not be fully complete yet"}
  start = Time.now
  out = render "views/main.ecr", "views/layout.ecr"
  puts "view took #{Time.now - start}"  # pre view takes as long as first query :|
  out
end

get "/getting_started" do |env|
  render "views/getting_started.ecr", "views/layout.ecr"
end

get "/privacy" do |env|
  render "views/privacy.ecr", "views/layout.ecr"
end

get "/faq" do |env|
  render "views/faq.ecr", "views/layout.ecr"
end

get "/login" do |env|
  if logged_in?(env)
    add_to_flash env, "already logged in!"
    env.redirect "/"
  else
    render "views/login.ecr", "views/layout.ecr"
  end
end

get "/delete_tag_edit_list/:url_id" do |env|
  url_id = env.params.url["url_id"].to_i
  tag_edit_list = TagEditList.get_existing_by_url_id url_id, user_id(env)
  tag_edit_list.destroy_tag_edit_list_to_tags
  tag_edit_list.destroy_no_cascade
  add_to_flash env, "deleted one tag edit list"
  env.redirect "/view_url/#{url_id}"
end


get "/personalized_edit_list/:url_id" do |env|
  url_id = env.params.url["url_id"].to_i
  tag_edit_list = TagEditList.get_only_by_url_id_or_nil url_id, user_id(env)
  tag_edit_list ||= TagEditList.new url_id, user_id(env)
    # and not save yet :|
  render "views/list_edit_tag_list.ecr", "views/layout.ecr"
end

post "/save_tag_edit_list" do |env|
  params = env.params.body # POST params
  url_id = params["url_id"].to_i
  if params["id"]?
    tag_edit_list = TagEditList.get_existing_by_url_id url_id, user_id(env)
    raise "wrong id? you gave #{params["id"]} expected #{tag_edit_list.id}" unless params["id"].to_i == tag_edit_list.id
  else
    tag_edit_list = TagEditList.new url_id, user_id(env)
  end

  tag_edit_list.description = resanitize_html params["description"]
  raise "must have name" unless tag_edit_list.description.present? # TODO rename db column :|
  tag_edit_list.status_notes = resanitize_html params["status_notes"]
  tag_edit_list.age_recommendation_after_edited = params["age_recommendation_after_edited"].to_i
  tag_ids = [] of Int32
  actions = [] of String
  env.params.body.each{ |name, value|
    if name =~ /tag_select_(\d+)/ # hacky but you have to go down hacky either in name or value since it maps there too :| [?]
      tag_ids << $1.to_i
      actions << value
    end
  }
  tag_edit_list.create_or_refresh(tag_ids, actions)
  add_to_flash(env, "Success! saved tag edit list #{tag_edit_list.description} if you are watching the movie in another browser tab please refresh that browser tab")
  save_local_javascript [tag_edit_list.url], tag_edit_list.inspect, env
  env.redirect "/view_url/#{tag_edit_list.url_id}" # back to the movie page...
end

def save_local_javascript(db_urls, log_message, env) # actually just json these days...
  db_urls.each { |db_url|
    [db_url.url, db_url.amazon_second_url].reject(&.empty?).each{ |url|
      File.open("edit_descriptors/log.txt", "a") do |f|
        f.puts log_message + " user:#{user_id(env)} ... " + db_url.name_with_episode
      end
      as_json = json_for(db_url, env)
      escaped_url_no_slashes = URI.escape url
      File.write("edit_descriptors/#{escaped_url_no_slashes}.ep#{db_url.episode_number}" + ".html5_edited.just_settings.json.rendered.js", "" + as_json) 
   }
  }
  if !is_dev?
    spawn do
      system("cd edit_descriptors && git checkout master && git pull && git add . && git cam \"#{log_message}\" && git push origin master") # backup :| I control log_message
    end
  end
end

def is_dev?
  File.exists?("./this_is_development")
end

def user_id(env)
  logged_in_user(env).id # could use user_id here but...that's somebody else's ID dunno...weird'ish...
end

def logged_in_user(env)
  if is_dev?
    User.new "test_user_id", "test_user_name", "test@test.com", "facebook" # and id 0
  else
   env.session.object("user") 
  end
end 

def resanitize_html(string)
  outy = HTML.unescape(string)
  sanitize_html outy # this is HTML.escape
end

def get_float(params, name)
  if params[name]? && params[name].present?
    params[name].to_f
  else
    0.0
  end
end

def get_int(params, name)
  if params[name]? && params[name].present?
    params[name].to_i
  else
   0
  end
end

post "/save_url" do |env|
  params = env.params.body # POST params
  puts "got save_url params=#{params}"
  if params.has_key? "id"
    # these day
    db_url = Url.get_only_by_id(params["id"])
  else
    db_url = Url.new
  end
  
  # these get injected into HTML later so sanitize everything up front... :|
  incoming_url = resanitize_html(params["url"])
  if db_url.url != incoming_url
    _ , incoming_url = get_title_and_sanitized_standardized_canonical_url HTML.unescape(incoming_url) # in case url changed make sure they didn't change it to a /gp/, ignore title since it's already here manually already :|
  end
  amazon_second_url = resanitize_html(params["amazon_second_url"])
  if amazon_second_url.present?
    _ , amazon_second_url = get_title_and_sanitized_standardized_canonical_url HTML.unescape(amazon_second_url)
  end

  db_url.name = resanitize_html(params["name"]) # resanitize in case previously escaped case of re-save [otherwise it grows and grows in error...]
  db_url.url = incoming_url
  db_url.details = resanitize_html(params["details"])
  db_url.editing_status = resanitize_html(params["editing_status"])
  db_url.amazon_second_url = amazon_second_url
  db_url.episode_number = get_int(params, "episode_number")
  db_url.episode_name = resanitize_html(params["episode_name"])
  db_url.wholesome_uplifting_level = get_int(params, "wholesome_uplifting_level")
  db_url.good_movie_rating = get_int(params, "good_movie_rating")
  db_url.review = resanitize_html(params["review"])
  db_url.wholesome_review = resanitize_html(params["wholesome_review"])
  db_url.amazon_prime_free_type = resanitize_html(params["amazon_prime_free_type"])
  db_url.rental_cost = get_float(params, "rental_cost")
  db_url.purchase_cost = get_float(params, "purchase_cost")
  db_url.total_time = human_to_seconds params["total_time"]
  db_url.genre = resanitize_html(params["genre"])
  db_url.original_rating = resanitize_html(params["original_rating"])
  db_url.editing_notes = resanitize_html(params["editing_notes"])
  db_url.community_contrib = params["community_contrib"] == "true" # the string
  db_url.save
  
  image_url = params["image_url"]
  if image_url.present?
    db_url.download_image_url_and_save image_url
  else
    download_youtube_image_if_none db_url
  end

  save_local_javascript [db_url], db_url.inspect, env
	
  add_to_flash(env, "Success! saved #{db_url.name_with_episode}")
  env.redirect "/view_url/" + db_url.id.to_s
end

def download_youtube_image_if_none(db_url)
  if !db_url.image_local_filename.present? && db_url.url =~ /youtube.com/
    # we can get an image fer free! :) The default ratio they seem to offer "wide horizon" unfortunately, though we might be able to do better XXXX
    youtube_id = db_url.url.split("?v=")[-1] # https://www.youtube.com/watch?v=9VH8lvZ-Z1g :|
    db_url.download_image_url_and_save "http://img.youtube.com/vi/#{youtube_id}/0.jpg"
  end
end

post "/upload_from_subtitles_post/:url_id" do |env|
  db_url = get_url_from_url_id(env)
  params = env.params.body # POST params
  add_to_beginning = params["add_to_beginning"].to_f
  add_to_end = params["add_to_end"].to_f
  
  if env.params.files["srt_upload"]? && env.params.files["srt_upload"].filename && env.params.files["srt_upload"].filename.not_nil!.size > 0 # kemal bug'ish :|?? also nil??
    db_url.subtitles = File.read(env.params.files["srt_upload"].tmpfile.path) # saves contents, why not? :) XXX save euphemized? actually original might be more powerful somehow...
    profs, all_euphemized = SubtitleProfanityFinder.mutes_from_srt_string(db_url.subtitles)
  elsif params["amazon_subtitle_url"]?
    db_url.subtitles = download(params["amazon_subtitle_url"])
    profs, all_euphemized = SubtitleProfanityFinder.mutes_from_amazon_string(db_url.subtitles)
  else
    raise "no subtitle file to parse?"
  end
  profs.each { |prof|
    tag = Tag.new(db_url)
    tag.start = prof[:start] - add_to_beginning
    tag.endy =  prof[:endy] + add_to_end
    tag.default_action = "mute"
    tag.category = "profanity"
    tag.subcategory = prof[:category]
    tag.details = prof[:details]
    tag.save
  }
  clean_subs = all_euphemized.reject{|p| p[:category] != nil }
  middle_sub = clean_subs[clean_subs.size / 2]
  puts "clean_subs = euphsize=#{all_euphemized.size} clean_size=#{clean_subs.size} idx=#{clean_subs.size / 2} middle_sub = #{middle_sub}"
  add_to_flash(env, "successfully uploaded subtitle file, created #{profs.size} mute tags from subtitle file. Please review them if you desire.")
  add_to_flash(env, "You should see [#{middle_sub[:details]}] at #{seconds_to_human middle_sub[:start]} if the subtitle file timing is right, please double check it using the \"frame\" button!")
  env.redirect "/view_url/" + db_url.id.to_s
end

def add_to_flash(env, string)
  if env.session.string?("flash")
    env.session.string("flash", env.session.string("flash") + "<br/>" + string)
  else
    env.session.string("flash", string)
  end
end

Kemal.run
sleep # needed for my cruddy restart after sync stuff?? :|
