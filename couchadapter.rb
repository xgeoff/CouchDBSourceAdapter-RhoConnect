require 'json'
require 'rest_client'

class Product < SourceAdapter

  def initialize(source,credential)
    # Place the base url for your couch db in the @base variable
    # e.g. @base = "http://127.0.0.1:5984"
    @base = "http://127.0.0.1:5984"
    # Place the name of the database that you will be connecting to in the @db variable
    # e.g. @db = "products"
    @db = "products"
    super(source,credential)
  end

  def query(params=nil)
    # the following uri will return all docs in the database
    # if you want to filter your results, implement views per the couchdb instructions
    # and call them accordingly.
    # Alternatively, you can return all of the docs and filter them before returning
    # the hash to the rhosync client. This is far less efficient, however.
    uri = "#{@base}/#{@db}/_all_docs?include_docs=true"
    parsed = JSON.parse(RestClient.get(uri).body)
    # create the result hash from the parsed response
    create_result_hash parsed
  end
  
  def create_result_hash(body)
    # set up the @result hash, which will contain data to be returned to the client
    @result = {}
    # fetch the rows from the document body
    rows = body["rows"]
    # iterate through the rows, extracting the document, removing the "_id" element
    # because we will use that as our record id in the @result hash and set the
    # doc in the @result hash
    rows.each do |item|
      doc = item["doc"]
      id = doc.delete("_id").to_s
      @result[id] = doc
    end if rows
    
  end
  
  # the following method illustrates how to inject data into the data management
  # system. the objects variable must be a hash of records where the key is a
  # string id and the value is a hash of the data attributes and values.
  def push_objects(objects)
    @source.lock(:md) do |s|
      doc = @source.get_data(:md)
      objects.each do |id,obj|
        doc[id] ||= {}
        doc[id].merge!(obj)
      end  
      @source.put_data(:md,doc)
      @source.update_count(:md_size,doc.size)
    end      
  end
  
  def reselect(id)
    # create the uri to select a single record
    uri = "#{@base}/#{@db}/#{id}"
    # call the uri and parse the return body
    parsed = JSON.parse(RestClient.get(uri).body)
    # set up the hash to pass to the push_objects method
    objects = {}

    # if parsed is not nil, remove the "_id" field of the record and push the
    # reselected record into data management
    if parsed
      objects[parsed.delete("_id").to_s] = parsed
      push_objects objects
    end 
  end

  def create(create_hash)
    # first check to see if the id has been created on the client
    id = create_hash.delete("id")
    
    if id == nil
      id = create_id(create_hash)
      
      if id == nil
        uri = "#{@base}/#{@db}"
        body = RestClient.post(uri, create_hash.to_json, :content_type => :json, :accept => :json).body
        parsed = JSON.parse(body)
        id = parsed["id"]
      else
        uri = "#{@base}/#{@db}/#{id}"
        RestClient.put(uri, create_hash.to_json, :content_type => :json, :accept => :json).body
      end
    end
    
    puts "The uri is: #{uri}"
    
    puts "the id is: #{id.to_s}"
    reselect id
    id
  end
  
  def create_id(create_hash)
    # You may create the id before insertion if desired.  Be sure to return the id from this method
    # if you are assigning it.
    id = "#{create_hash['brand']}#{create_hash['name']}"
  end

  def update(update_hash) 
    # obtain the id for the record to be updated
    id = update_hash['id']
    # remove the id from the hash, we'll utilize it in the uri
    update_hash.delete('id')
    uri = "#{@base}/#{@db}/#{id}"
    # perform the update
    RestClient.put(uri, update_hash.to_json, :content_type => :json, :accept => :json)
    # after the update, reselect the record as changes will have occurred to the record
    # e.g. the _rev will be updated
    reselect id

  end

  def delete(delete_hash)   
    RestClient.delete("#{@base}/#{@db}/#{delete_hash['id']}?rev=#{delete_hash['_rev']}")
  end

end 