module TemplatesHelper
  def dialogue_types_for_select
    ConversationTemplates.dialogue_types_by_category.map do |category, types|
      [
        category,
        types.map { |key, type| [ type[:name], key ] }
      ]
    end
  end

  def character_archetypes_for_select
    ConversationTemplates.characters_by_category.map do |category, characters|
      [
        category,
        characters.map { |key, character| [ character[:name], key ] }
      ]
    end
  end

  def suggested_combinations_for_select
    ConversationTemplates::SUGGESTED_COMBINATIONS.map do |combo|
      [ combo[:name], combo[:name] ]
    end
  end

  def get_dialogue_type_data(key)
    ConversationTemplates.get_dialogue_type(key)
  end

  def get_character_data(key)
    ConversationTemplates.get_character(key)
  end

  def get_combination_data(name)
    ConversationTemplates.get_combination(name)
  end
end
