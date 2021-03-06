require 'json'
require 'kramdown'
require 'csv'
require 'iiif/presentation'
require 'rsolr'
require 'nokogiri'
require 'fileutils'
require 'uri'
require 'open3'
require 'httparty'

# rvm use 2.4.0@bartram

def split_pdfs(directory_name, image_directory)
	puts 'in split_pdfs'
	Dir.mkdir(image_directory) unless Dir.exist?(image_directory)
	Dir.chdir(directory_name)
	Dir.glob('**/*.pdf').each { |pdf| 
		Dir.chdir(directory_name)
		name = File.basename(pdf)
		path = File.realpath(pdf)
		number, rest = name.split('_')
		newdir = File.join(image_directory, number)
		Dir.mkdir(newdir) unless Dir.exist?(newdir)
		Dir.chdir(newdir)
		`convert -density 150 '#{path}' -quality 100 image-#{number}-%02d.jpg` 
	}
end

def docx_to_md(directory_name, output_directory)
	puts 'in docx_to_md'
	Dir.chdir(directory_name)
	Dir.glob('**/*.docx').each { |docx| 
		Dir.chdir(directory_name)
		name = File.basename(docx)
		path = File.realpath(docx)
		number, rest = name.split('_')
		newdir = File.join(output_directory, number)
		FileUtils.mkdir_p(newdir) unless Dir.exist?(newdir)
		Dir.chdir(newdir)
		`pandoc -t markdown -o description-#{number}.md "#{path}"` 
	}	
end

def notebookdocx_to_md(directory_name, output_directory)
	FileUtils.mkdir_p(output_directory) unless Dir.exist?(output_directory)
	Dir.chdir(directory_name)
	Dir.glob('**/*.docx').each { |docx| 
		Dir.chdir(directory_name)
		path = File.realpath(docx)
		name = File.basename(docx, '.docx')
		Dir.chdir(output_directory)
		`pandoc -t markdown -o "#{name}.md" "#{path}"` 
	}	
end

def copy_images(source,out,start)
	Dir.chdir(source)
	Dir.glob('**/*.jpg').each_with_index { |jpg, i|
		#break if i > 3
		path = File.realpath(jpg)
		name = File.basename(jpg)
		n = name.split("-")[1].to_i
		if n > start
			puts "p:" + path
			puts "n:" + name
			FileUtils.cp path, out+ "/" + name
		end
	}
end

def copy_scan_metadata(source,out,start)
	puts 'copy_scan_metadata'
	Dir.chdir(source)
	Dir.glob('**/*.json').each_with_index { |json, i|
		#break if i > 3
		path = File.realpath(json)
		name = File.basename(json)
		n = name.split("-")[1].to_i
		if n > start
			puts "p:" + path
			puts "n:" + name
			FileUtils.cp path, out+ "/" + name
		end
	}
end


def load_scan_metadata(image_directory) 
  metadata = Hash.new
  File.open(File.join(image_directory, "scans_metadata_edited.tsv"), 'r').each_line { |line| 
    binder, id, creator, subject, type, description, institution, other = line.split("\t")
    metadata[id] = {
      creator: creator,
      subject: subject,
      description: description,
      institution: institution
    }      
  }
  metadata
end

def generate_metadata(directory_name, image_directory)
	puts "in generate_metadata"
	Dir.chdir(directory_name)
	#csv = CSV.open(File.join(image_directory, "metadata.csv"), 'w')
	#csv << ['ID', 'Creator', 'Subject', 'Type',  'Description', 'Location', 'Within', 'Contents', 'Recto', 'Verso', 'Photo', 'Institutional Stamp']
    #corrected = load_scan_metadata(image_directory)
	corrected = load_scan_metadata("/Users/erjhome/RubymineProjects/Amy_Natural_History/images")
  puts "dir name:"+directory_name
	Dir.glob('**/*.docx').each { |pdf| 
		Dir.chdir(directory_name)
		name = File.basename(pdf)
		name.gsub!('.docx', '')
		number, last_name, first_name, subject, type = name.split('_')
		if number.length > 4 || number.start_with?('~')
			puts "Skipping #{number}"
			next
		end
		newdir = File.join(image_directory, number)
		Dir.mkdir(newdir) unless Dir.exist?(newdir)
		Dir.chdir(newdir)
		metadata = Hash.new
                
		corrected_metadata = corrected[number.to_i.to_s] || {}
    	subject = corrected_metadata[:subject] || subject
    	description = corrected_metadata[:description] || description
    	creator = corrected_metadata[:creator] || "#{last_name}, #{first_name}"

		metadata['creator'] = creator
		metadata['id'] = "scan-#{number}"
		metadata['subject'] = subject if subject
		metadata['type'] = type if type
		metadata['location'] = corrected_metadata[:institution]

		pdf.match(/Binder\d/) { |binder|
			b = binder[0].gsub!('Binder', 'Binder ')
			metadata['within'] = b
		}

		markdown = File.read("description-#{number}.md")
		description = ""
		markdown.each_line { |line|
			description += line.strip + " "
			break if line.strip!.empty?
		}
		description.gsub!('\n', '')
		description = Kramdown::Document.new(description, input: 'GFM').to_html  
		description.gsub!('<p>', '')
		description.gsub!('</p>', '')
		description.gsub!('&amp;', '&')
		metadata['label'] = description
		metadata['description'] = description
		
		markdown.match(/Contents: (.*)\.$/) { |m|
			metadata['contents'] = m[1];
		}
		start, label, verso = markdown.partition('**Verso**:')
		start, label, recto = start.partition('**Recto**:')
		verso, label, institutional_stamp = verso.partition(/Institutional (stamp|Stamp|label|Label):/)
		verso, label, photo = verso.partition('Photo:')
		metadata['recto'] =  Kramdown::Document.new(recto, input: 'GFM').to_html unless recto.empty?
		metadata['verso'] =  Kramdown::Document.new(verso, input: 'GFM').to_html unless verso.empty?
		metadata['photo'] =  Kramdown::Document.new(photo, input: 'GFM').to_html unless photo.empty?
		metadata['institutional_stamp'] = Kramdown::Document.new(institutional_stamp, input: 'GFM').to_html unless institutional_stamp.empty?
		# write JSON
		file = File.open(File.join(newdir, "metadata-#{number}.json"), 'w')
		file.write( JSON.pretty_generate(metadata) )
		file.close
		# write CSV
		array = metadata.values_at('id', 'creator', 'subject', 'type', 'description', 'location', 'within', 'contents', 'recto', 'verso', 'photo', 'institutional_stamp')
		#csv << array
	}	
	#csv.close
end

def generate_manifests(image_directory, url_prefix, manifest_directory)
	puts 'in generate_manifests'
	FileUtils.mkdir_p(manifest_directory) unless Dir.exist?(manifest_directory)
	Dir.chdir(image_directory)
	Dir.glob('**/metadata-*.json').each_with_index { |md,i|
		#break if i > 2
		Dir.chdir(image_directory)
		metadata = JSON.parse(File.read(md))
		iiif_metadata = Array.new
		display_metadata = metadata.clone
		display_metadata.delete('id')
		display_metadata.delete('label')
		display_metadata.delete('description')
		display_metadata.each_key { |k|	
			iiif_metadata.push({ "label" => k.capitalize, "value" => metadata[k] })
		}
		Dir.chdir(File.dirname(md))

		seed = {
			'@id' => "#{url_prefix}/manifest/#{metadata['id']}",
			'label' => metadata['label'],
			'description' => metadata['description']
		}
		manifest = IIIF::Presentation::Manifest.new(seed)
		manifest.viewing_hint = 'individuals'
		manifest.metadata = iiif_metadata
		sequence = IIIF::Presentation::Sequence.new()
		sequence.label = "Default sequence"
		sequence['@id'] = "#{url_prefix}/sequence/#{metadata['id']}"
		manifest.sequences << sequence
		Dir.glob('*.jpg').each { |image|
			image_path = File.realpath(image)
			image_basename = File.basename(image,'.jpg')
			width, height = `identify -format '%w %h' #{image_path}`.split(' ')
			canvas = IIIF::Presentation::Canvas.new()
			canvas['@id'] = "#{url_prefix}/canvas/#{image_basename}"
			canvas.label = image_basename
			canvas.width = width.to_i
			canvas.height = height.to_i
			annotation = IIIF::Presentation::Annotation.new()
			annotation['@id'] = "#{url_prefix}/annotation/#{image_basename}"
			image = IIIF::Presentation::ImageResource.create_image_api_image_resource({				
				service_id: "#{url_prefix}/image-service/#{image_basename}",
				width: width.to_i, 
				height: height.to_i, 
				profile:'http://iiif.io/api/image/2/profiles/level2.json'})
			annotation.resource = image
			canvas.images << annotation
			sequence.canvases << canvas
		}
		manifest_filename = File.basename(md)
		manifest_filename.gsub!('metadata-','scan-')
		file = File.open("#{manifest_directory}/#{manifest_filename}", 'w')
		json = manifest.to_json(pretty: true)
		file.write(json)
		file.close
	}
end		

def index_scans(image_directory,solr_url)
	puts 'in index scans'
	solr = RSolr.connect :url => solr_url
	Dir.chdir(image_directory)
	Dir.glob('**/metadata-*.json').each { |md|
		Dir.chdir(image_directory)
		metadata = JSON.parse(File.read(md))
		doc = Hash.new
		doc[:id] = metadata['id']
		doc[:title_display] = metadata['label'] 
		doc[:title_t] = metadata['label'] 
		doc[:text] = "#{metadata['label']} #{metadata['recto']} #{metadata['verso']}"
		doc[:subject_topic_facet] = metadata['subject']
		doc[:subject_topic_s] = metadata['subject']
		doc[:gnrd_sm] = get_gnrd(metadata['label'])
		doc[:author_display] = metadata['creator']
		doc[:author_t] = metadata['creator']
		doc[:author_unstem_search] = metadata['creator']
		doc[:author_display_facet] = metadata['creator']
		doc[:iiif_manifest_s] = "https://s3.amazonaws.com/bertrammanifests/#{metadata['id']}.json"
		doc[:iiif_thumbnail_s] = "http://localhost:3000/image-service/#{metadata['id'].gsub('scan','image')}-00/full/150,150/0/default.jpg"
		doc[:part_of_facet] = metadata['within']
		doc[:part_of_s] = metadata['within']
		doc[:location_facet] = metadata['location']
		doc[:location_s] = metadata['location']
		doc[:contents_s] = metadata['contents']
		doc[:recto_s] = metadata['recto']
		doc[:verso_s] = metadata['verso']
		doc[:photo_s] = metadata['photo']
		doc[:institutional_stamp_s] = metadata['institutional_stamp']
		doc[:format] = 'scan'
		doc[:object_type_s] = "scan"
		doc[:timestamp] = Time.now.utc
		solr.add doc
	}
	solr.commit
end

def get_gnrd(label)
	s = "http://gnrd.globalnames.org/name_finder.json"
	f = "object_tmp.txt"
	open(f, 'w') { |f|
		f.puts label
	}
	cmd = 'curl -D - -F "file=@'+f+'" '+s
	l = ""
	Open3.popen3(cmd) do |stdin, stdout, stderr, wait_thr|
		l = stdout.readlines[8].gsub("Location: ","").strip
	end
	a = Array.new
	response = HTTParty.get(l)
	json = JSON.parse(response.body)
	json["names"].each do |name|
		a.push(name["scientificName"])
	end

	puts "gnrd:" + a.inspect
	return a
end

def index_notebooks(markdown_notebooks, solr_url)
	solr = solr = RSolr.connect :url => solr_url
	Dir.chdir(markdown_notebooks)
	Dir.glob('*.md').each { |md|
		puts md
		next unless md.start_with?("entry")
		markdown = File.read(md)
		markdown.gsub!(/^   /, '  ')
-
		if (markdown.length > 32000) 
			puts "**** #{md} too long"
		end

		basename = File.basename(md, '.md')
		cat, subject = basename.split('-')
		entry_s, book_s, repo = cat.split('_')
		entry_s.gsub!('entry', '')
		entry_s = entry_s.to_i
		entry = "%02d" % entry_s.to_i
		book_s.gsub!('book', '')
		book = "%02d" % book_s.to_i
		within = "Notebook #{book_s}"
		id = "notebook-#{book}-#{entry}"
		label = "Notebook #{book_s}, Entry #{entry_s}, #{subject}"
		subject.strip! unless subject.nil? or subject.empty?
		location = 'Yale Center for British Art'

		
		doc = Hash.new
		doc[:id] = id
		doc[:title_display] = label 
		doc[:title_t] = label
		doc[:text] = markdown
		doc[:subject_topic_facet] = subject
		doc[:subject_topic_s] = subject
		doc[:author_display] = 'Meyers, Amy'
		doc[:author_t] = 'Meyers, Amy'
		doc[:author_unstem_search] = 'Meyers, Amy'
		doc[:author_display_facet] = 'Meyers, Amy'
		doc[:timestamp] = Time.now.utc.iso8601
		doc[:part_of_facet] = within
		doc[:part_of_s] = within
		doc[:location_facet] = location
		doc[:location_s] = location
		doc[:fulltext_s] = markdown
		doc[:format] = 'text'
		solr.add doc
	}
	solr.commit
end

#solr_url = 'http://127.0.0.1:8983/solr/blacklight-core'
solr_url = 'http://127.0.0.1:8983/solr/bertram2'
#solr_url = 'http://ec2-54-91-198-228.compute-1.amazonaws.com:8983/solr/blacklight-core'


# CHANGE THIS
root_directory = '/Users/erjhome/RubymineProjects/Amy_Natural_History'
root_directory_new = '/Users/erjhome/RubymineProjects/Amy_Natural_History/erj'

directory_name = "#{root_directory}/Meyers Natural History_Binders"
notebook_directory_name = "#{root_directory}/Meyers Natural History_Notebooks"
#image_directory = "#{root_directory}/images"
#markdown_notebooks = "#{root_directory}/notebook_markdown"
#manifest_directory = "#{root_directory}/manifests"

#new set of output directories
image_directory = "#{root_directory_new}/images"
markdown_notebooks = "#{root_directory_new}/notebook_markdown"
manifest_directory = "#{root_directory_new}/manifests"


url_prefix = 'http://ec2-54-91-198-228.compute-1.amazonaws.com:3000'

#docx_to_md(directory_name, image_directory) #ERJ
#generate_metadata(directory_name, image_directory)
#generate_manifests(image_directory, url_prefix, manifest_directory)
#index_scans(image_directory, url_prefix, solr_url)

#notebookdocx_to_md(notebook_directory_name, markdown_notebooks)
#index_notebooks(markdown_notebooks, solr_url)

#ERJ to specifically get Binder 9 jpgs
source_pdfs = '/Users/erjhome/RubymineProjects/Amy_Natural_History/Meyers Natural History_Binders/Binder9/Scans' #scan pdfs
source = '/Users/erjhome/RubymineProjects/Amy_Natural_History/Meyers Natural History_Binders/Binder9' #scan docx
out = '/Users/erjhome/RubymineProjects/Amy_Natural_History/images'
#split_pdfs(source_pdfs,out)
#docx_to_md(source,out)
#generate_metadata(source,out)

#ERJ to copy /images to iiif-image
#source = '/Users/erjhome/RubymineProjects/Amy_Natural_History/images'
#out = '/Users/erjhome/RubymineProjects/Amy_Natural_History/iiif-images'
#copy_images(source,out,779)

#ERJ to copy json to component_md/solrscans
#source = '/Users/erjhome/RubymineProjects/Amy_Natural_History/images'
#out = '/Users/erjhome/RubymineProjects/Amy_Natural_History/component_md/solrscans'
#copy_scan_metadata(source,out,779)


#ERJ generate manifest with localhost:3000/image-service
image_directory = '/Users/erjhome/RubymineProjects/Amy_Natural_History/images'
#url_prefix = 'http://localhost:3000' #local_manifests
url_prefix = 'http://10.5.96.214:3000' #instance_manifests
manifest_directory = "/Users/erjhome/RubymineProjects/Amy_Natural_History/instance_manifests"
generate_manifests(image_directory, url_prefix, manifest_directory)

#ERJ index scans - now up to 806
#image_directory = '/Users/erjhome/RubymineProjects/Amy_Natural_History/images'
#index_scans(image_directory,solr_url)
