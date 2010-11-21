require File.dirname(__FILE__) + '/../spec_helper'

describe Synonym do
  before(:all) do
    load_foundation_cache
    @tc = build_taxon_concept
    @curator = build_curator(@tc)
    @another_curator = build_curator(@tc)
    @lang = Language.english
    # Certain ActionWithObjects and ChangeableObjectTypes need to exist for these to work (but they may already exist):
    ActionWithObject.create(:action_code => 'trust') rescue nil
    ActionWithObject.create(:action_code => 'untrust') rescue nil
    ActionWithObject.create(:action_code => 'unreview') rescue nil
    ChangeableObjectType.create(:ch_object_type => 'synonym') rescue nil
  end

  describe "preferred=" do
    it "when preffered name is set for a synonym all other synonyms of this language should get set preferred to false" do
      syn1 = @tc.add_common_name_synonym("First name", :agent => @curator.agent, :language => @lang)
      TaxonConceptName.find_by_synonym_id(syn1.id).preferred?.should be_true
      syn2 = @tc.add_common_name_synonym("Second name", :agent => @curator.agent, :language => @lang)
      TaxonConceptName.find_by_synonym_id(syn2.id).preferred?.should be_false
      syn2.preferred = 1
      syn2.save!
      Synonym.find(syn2).preferred?.should be_true
      TaxonConceptName.find_by_synonym_id(syn2.id).preferred?.should be_true
      Synonym.find(syn1).preferred?.should be_false
      TaxonConceptName.find_by_synonym_id(syn1.id).preferred?.should be_false
    end
  end

end
