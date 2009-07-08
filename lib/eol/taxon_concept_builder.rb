class EOL

  class TaxonConceptBuilder

    attr_reader :tc

    include EOL::Spec::Helpers

    # == Options:
    #
    # These all have intelligent(ish) default values, so just specify those values that you feel are really salient. Note that a TC will
    # NOT have a map or an IUCN status unless you specify options that create them.
    #
    #   +attribution+::
    #     String to be used in scientific name as attribution
    #   +canonical_form+::
    #     String to use for canonical form (all names will reference this)
    #   +comments+::
    #     Array of hashes.  Each hash can have a +:body+ and +:user+ key.
    #   +common_names+::
    #     String to use for thre preferred common name
    #   +depth+::
    #     Depth to apply to the attached hierarchy entry.  Don't supply this AND rank.
    #   +flash+::
    #     Array of flash videos, each member is a hash for the video options.  The keys you will want are
    #     +:description+ and +:object_cache_url+.
    #   +id+::
    #     Forces the ID of the TaxonConcept to be what you specify, useful for exemplars.
    #   +images+::
    #     Array of hashes.  Each hash may have the following keys: +:description+, +:hierarchy_entry+,
    #     +:object_cache_url+, +:taxon+, +:vetted+, +:visibility+ ...These are the args used to call
    #     #build_data_object
    #   +italicized+::
    #     String to use for preferred scientific name's italicized form.
    #   +iucn_status+::
    #     String to use for IUCN description, OR just set to true if you want a random IUCN status instead.
    #   +gbif_map_id+::
    #     The ID to use for the Map Data Object.
    #   +parent_hierarchy_entry_id+::
    #     When building the associated HierarchyEntry, this id will be used for its parent.
    #   +rank+::
    #     String form of the Rank you want this TC to be.  Default 'species'.
    #   +scientific_name+::
    #     String to use for the preferred scientific name.
    #   +toc+::
    #     An array of hashes.  Each hash may have a +:toc_item+ key and a +:description+ key.
    #   +youtube+::
    #     Array of YouTube videos, each member is a hash for the video options.  The keys you will want are
    #     +:description+ and +:object_cache_url+.
    # TODO - stop using @options and just store everthing in instance vars.
    # TODO - Create a harvest event and a resource (status should be published) (and the resource needs a hierarchy, which we use for
    # the HEs)
    # TODO - Normalize names ... when harvesting is done, this is done on-the-fly, so we should do it here.
    def initialize(options)
      @debugging = false
      puts "** Enter: initialize" if @debugging
      @options     = options
      set_default_options
      build
    end
    
  private

    def build
      puts "** Enter: build" if @debugging
      gen_taxon_concept
      gen_name
      add_curator
      add_comments
      gen_taxon
      add_images
      add_videos
      add_map
      add_toc
      add_iucn
      gen_random_taxa
      gen_bhl
    end

    def gen_taxon_concept
      puts "** Enter: gen_taxon_concept" if @debugging
      # TODO - in the future, we may want to be able to muck with the vetted *and* the published fields...
      @tc    = nil # scope...
      # HACK!  We need to force the IDs of one of the TaxonConcepts, so that the exmplar array isn't empty.  I
      # hate to do it this way, but, alas, this is how it currently works:
      if @options[:id]
        @tc = TaxonConcept.find(@options[:id]) rescue nil
        if @tc.nil?
          @tc = TaxonConcept.gen(:vetted => Vetted.trusted)
          TaxonConcept.connection.execute("UPDATE taxon_concepts SET id = #{@options[:id]} WHERE id = #{@tc.id}")
          @tc = TaxonConcept.find(@options[:id])
        end
      else
        @tc = TaxonConcept.gen(:vetted => Vetted.trusted)
      end
    end

    # TODO - add some alternate names, including at least one in another language.
    # TODO - create alternate scientific names... just make sure the relation makes sense and the language_id is
    # either 0 or Language.scientific.
    def gen_name
      puts "** Enter: gen_name" if @debugging
      # Note that this assumes the ranks are *in order* which is ONLY true with foundation loaded!
      @depth = @options[:depth] || Rank.find_by_label(@options[:rank] || 'species').id - 1 # This is an assumption...
      @he    = build_entry_in_hierarchy(:parent_id => @options[:parent_hierarchy_entry_id])
      TaxonConceptName.gen(:preferred => true, :vern => false, :source_hierarchy_entry_id => @he.id,
                           :language => Language.scientific, :name => @sname, :taxon_concept => @tc)
      unless @cname.nil?
        TaxonConceptName.gen(:preferred => true, :vern => true, :source_hierarchy_entry_id => @he.id,
                             :language => Language.english, :name => @cname, :taxon_concept => @tc)
      end
      # TODO - create the Synonym here, with the Language of English, the SynonymRelation of Common Name, and the HE we just
      # created, and preferred...
      # NOTE: when we denormalize the taxon_concept_names table, we should be looking at Synonyms as well as Names.
    end

    def add_curator
      puts "** Enter: add_curator" if @debugging
      @curator = build_curator(@he)
    end

    def add_comments
      puts "** Enter: add_comments" if @debugging
      # Array with three empty hashes (default #), which we will populate with defaults:
      comments = @options[:comments] || [{}, {}]
      comments.each do |comment|
        comment[:body]  ||= "This is a witty comment on the #{@canon} taxon concept. Any resemblance to comments real" +
                            'or imagined is coincidental.'
        comment[:user] ||= User.count == 0 ? User.gen : User.all.rand
        Comment.gen(:parent => @tc, :parent_type => 'taxon_concept', :body => comment[:body], :user => comment[:user])
      end
    end

    def gen_taxon
      puts "** Enter: gen_taxon" if @debugging
      @taxon = Taxon.gen(:name => @sname, :hierarchy_entry => @he, :scientific_name => @complete) # Okay that we don't set kingdom, phylum, etc
      # TODO - Need a HarvestEventsTaxon entry here
      # TODO - Create some references here ... just a string and an associated identifier (like a URL)
    end

    def add_images
      puts "** Enter: add_images" if @debugging
      @options[:images].each do |img|
        description             = img.delete(:description) || Faker::Lorem.sentence
        img[:taxon]           ||= @taxon
        @images << build_object_in_event('Image', description, img)
      end
    end

    def add_videos
      puts "** Enter: add_videos" if @debugging
      flash_options = @options[:flash] || [{}] # Array with one empty hash, which we will populate with defaults:
      flash_options.each do |flash_opt|
        flash_opt[:description]      ||= Faker::Lorem.sentence
        flash_opt[:object_cache_url] ||= Factory.next(:flash)
        build_object_in_event('Flash', flash_opt[:description], :taxon => @taxon,
                              :object_cache_url => flash_opt[:object_cache_url])
      end

      youtube_options = @options[:youtube] || [{}] # Array with one empty hash, which we will populate with defaults:
      youtube_options.each do |youtube_opt|
        youtube_opt[:description]      ||= Faker::Lorem.sentence
        youtube_opt[:object_cache_url] ||= Factory.next(:youtube)
        build_object_in_event('YouTube', youtube_opt[:description], :taxon => @taxon,
                              :object_cache_url => youtube_opt[:object_cache_url])
      end
    end

    def add_iucn
      puts "** Enter: add_iucn" if @debugging
      if @options[:iucn_status]
        iucn_status = @options[:iucn_status] == true ? Factory.next(:iucn) : @options[:iucn_status]
        build_iucn_entry(@tc, iucn_status, :depth => @depth)
      end
    end

    def add_map
      puts "** Enter: add_map" if @debugging
      if @options[:gbif_map_id] 
        #gbif_he = build_hierarchy_entry(@depth, @tc, @sname, :hierarchy => gbif_hierarchy, :map => true,
        puts "++ Add map!" if @debugging
        puts "GBIF hierarchy:" if @debugging
        pp gbif_hierarchy if @debugging
        gbif_he = build_entry_in_hierarchy(:hierarchy => gbif_hierarchy, :map => true,
                                           :identifier => @options[:gbif_map_id])
        gbif_taxon = Taxon.gen(:name => @sname, :hierarchy_entry => @he, :scientific_name => @complete)
        HarvestEventsTaxon.gen(:taxon => gbif_taxon, :harvest_event => gbif_harvest_event)
      end
    end

    def add_toc
      puts "** Enter: add_toc" if @debugging
      @options[:toc].each do |toc_item|
        toc_item[:toc_item]    ||= TocItem.all.rand
        toc_item[:description] ||= Faker::Lorem.paragraph
        build_object_in_event('Text', toc_item[:description], :taxon => @taxon, :toc_item => toc_item[:toc_item])
      end
      # We're missing the info items.  Technically, the toc_item would be referenced by looking at the info items (creating any we're
      # missing).  TODO - we should build the info item first and let the toc_item resolve from that.
      # TODO BHL - just create an entry in each of the four special tables, linked to any of the names.
      # TODO Outlinks: create a Collection related to any agent, and then give it a mapping with a foreign_key that links to some external
      # site. (optionally, you could use collection.uri and replace the FOREIGN_KEY bit)
    end

    def gen_random_taxa
      puts "** Enter: gen_random_taxa" if @debugging
      return if @images.blank? or @sname.blank?
      # TODO - we really don't want to denomalize the names, so remove them (but check that this will work!)
      options = {:language => Language.english, :data_object => @images.last, :name_id => @sname.id,
                 :image_url => @images.last.object_cache_url, :name => @sname.italicized, :content_level => 4,
                 :taxon_concept => @tc,
                 :thumb_url => @images.first.object_cache_url}
      options[:common_name_en] = @cname.string unless @cname.blank?
      RandomTaxon.gen(options)
    end

    # TODO - This is one of the slower methods.
    # TODO - this comment should be integrated into the comment for the whole module
    # :bhl => [{:publication => 'Foobar', :page => 23}, {:publication => 'Bazboozer', :page => 78}]
    def gen_bhl
      puts "** Enter: gen_bhl" if @debugging
      @options[:bhl].each do |bhl|
        publication = nil # scope
        if bhl[:publication].nil?
          publication = default_publication
        else 
          publication = PublicationTitle.find_by_title(bhl[:publication])
          publication ||= PublicationTitle.gen(:title => bhl[:publication])
        end
        page = bhl[:page].to_i || (rand(400) + 1).to_i
        ti   = TitleItem.gen(:publication_title => publication)
        ip   = ItemPage.gen(:title_item => ti)
        pn   = PageName.gen(:item_page => ip, :name => @sname)
      end
    end

    def build_entry_in_hierarchy(options)
      puts "**** Enter: build_entry_in_hierarchy" if @debugging
      raise "Cannot build a HierarchyEntry without depth, TaxonConcept, and Name" unless @depth && @tc && @sname
      options[:hierarchy] ||= @hierarchy
      return build_hierarchy_entry(@depth, @tc, @sname, options)
    end

    # TODO - this is one of the slowest events (and it's called a lot!)
    def build_object_in_event(type, description, options = {})
      puts "**** Enter: build_object_in_event" if @debugging
      options[:event] ||= @event
      build_data_object(type, description, options)
    end

    # TODO - Too long: break this up
    def set_default_options
      puts "** Enter: set_default_options" if @debugging
      @attri        = @options[:attribution]     || Factory.next(:attribution)
      @common_names = @options[:common_names]    || [] # MOST entries should NOT have a common name.
      @canon        = @options[:canonical_form]  || Factory.next(:scientific_name)
      @complete     = @options[:scientific_name] || "#{@canon} #{@attri}".strip
      @hierarchy    = @options[:hierarchy]       || nil # We'll let build_hierarchy_entry pick a default
      @event = @options[:event] || default_harvest_event
      @images = [] # This is used to build the RandomTaxon
      if @options[:toc].nil?
        @options[:toc] = [{:toc_item => TocItem.overview, :description => "This is an overview of the <b>#{@canon}</b> hierarchy entry."},
                         {:toc_item => TocItem.find_by_label('Description'), :description => "This is an description of the <b>#{@canon}</b> hierarchy entry."}]
        # Add more toc items:
        (rand(4)+1).times do
          @options[:toc] << {} # Default values are applied below.
        end
      end
      if @options[:images].nil?
        @options[:images] = [{:num_comments => 12}] # One "normal" image, lots of comments, everything else default.
        # So, every TC (which doesn't have a predefined list of images) will have each of the following, making
        # testing easier:
        @options[:images] << {:description => 'untrusted', :object_cache_url => Factory.next(:image),
                              :vetted => Vetted.untrusted}
        @options[:images] << {:description => 'unknown',   :object_cache_url => Factory.next(:image),
                              :vetted => Vetted.unknown}
        @options[:images] << {:description => 'invisible', :object_cache_url => Factory.next(:image),
                              :visibility => Visibility.invisible}
        @options[:images] << {:description => 'preview', :object_cache_url => Factory.next(:image),
                              :visibility => Visibility.preview}
        @options[:images] << {:description => 'invisible, unknown', 
                              :object_cache_url => Factory.next(:image), :visibility => Visibility.invisible,
                              :vetted => Vetted.unknown}
        @options[:images] << {:description => 'invisible, untrusted', 
                              :object_cache_url => Factory.next(:image), :visibility => Visibility.invisible,
                              :vetted => Vetted.untrusted}
        @options[:images] << {:description => 'preview, unknown', 
                              :object_cache_url => Factory.next(:image), :visibility => Visibility.preview,
                              :vetted => Vetted.unknown}
        @options[:images] << {:description => 'inappropriate', 
                              :object_cache_url => Factory.next(:image), :visibility => Visibility.inappropriate}
      end
      if @options[:bhl].nil?
        @options[:bhl] = [{:publication => 'Great Big Journal of Fun', :page => 42},
                          {:publication => 'Great Big Journal of Fun', :page => 44},
                          {:publication => 'The Journal You Cannot Afford', :page => 1}]
      end
      @cform = CanonicalForm.find_by_string(@canon) || CanonicalForm.gen(:string => @canon)
      @sname = Name.gen(:canonical_form => @cform, :string => @complete,
                        :italicized     => @options[:italicized] || "<i>#{@canon}</i> #{@attri}".strip)
      # TODO - This should also create an entry in Synonyms (see below) (don't need agents_synonyms though)
      cname_objects = []
      @common_names.each do |common_name|
        cname_objects << Name.gen(:canonical_form => @cform, :string => common_name, :italicized => common_name)
      end
      @cname = cname_objects.first
    end

  end

end
