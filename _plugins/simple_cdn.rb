class SimpleCdnTag < Liquid::Tag
  def initialize(tag_name, input, tokens)
    super
    @input = input
  end

  def lookup(context, name)
    lookup = context
    name.split(".").each { |value| lookup = lookup[value] }
    lookup
  end

  def render(context)
    baseurl = "#{lookup(context, 'site.simple_cdn.url')}"
    env = "#{lookup(context, 'jekyll.environment')}"

    if env == "production"
      url = "{{ #{@input} | prepend: \"#{baseurl}\" }}"
    else
      url = "{{ #{@input} | relative_url }}"
    end
    return Liquid::Template.parse(url).render(context)
  end
end
Liquid::Template.register_tag('simple_cdn', SimpleCdnTag)