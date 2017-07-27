require 'digest'

class PipelineGenerator

  def initialize
    @images = []
  end

  def add(image_desc, base_path)
    dockerfile_path = File.join('toolsmiths-images', base_path, 'Dockerfile')
    test_script_path = File.join(base_path, 'test.sh')
    @images << DockerImage.new(image_desc, dockerfile_path, test_script_path)
  end

  def jobs_by_name
    to_h['jobs'].reduce({}) {|hash, job|
      hash[job['name']] = job
      hash
    }
  end

  def resources_by_name
    to_h['resources'].reduce({}) {|hash, resource|
      hash[resource['name']] = resource
      hash
    }
  end

  def to_h
    {
      'jobs' => image_jobs,
      'resources' =>
        [JobResources.toolsmiths_git_resource] + image_job_resources
    }
  end

  def generate
    remove_quoting_around_concourse_placeholders(to_h.to_yaml)
  end

private

  def image_jobs
    @images.map{|image|
      job_resources = JobResources.new(image, dependency_names)
      DockerImageJob.new(image, job_resources).to_h
    }
  end

  def image_job_resources
    @images.reduce([]) {|list, image|
      job_resources = JobResources.new(image, dependency_names)
      list << job_resources.untested_image_resource
      list << job_resources.final_image_resource
      list += job_resources.s3_resources
    }.reduce({}) {|hash, resource|
      hash[resource['name']] = resource
      hash
    }.values
  end

  def remove_quoting_around_concourse_placeholders(yaml)
    yaml.gsub(/['"]({{.*}})['"]/, '\1')
  end

  def dependency_names
    names = {}
    @images.each{|image|
      image.dependencies.each{|dep|
        names[dep.md5] = dep.name
      }
    }
    names.values
  end
end

class DockerImageJob

  def initialize(image, job_resources)
    @image = image
    @job_resources = job_resources
  end

  def to_h
    {
      'name' => build_name,
      'max_in_flight' => 1,
      'plan' => [{
        'timeout' => '3h',
        'do' =>
          source_repo_get_step +
          upstream_get_step +
          s3_gets +
          build_image_step +
          test_image_step +
          push_image_step
      }]
    }
  end

private

  def build_name
    'build-' + @image.name
  end

  def source_repo_get_step
    [remove_nil_values({
      'get' => 'toolsmiths-images',
      'passed' => has_upstream_image? ? [upstream_build_name] : nil,
      'trigger' => has_upstream_image? ? nil : true
    })]
  end

  def upstream_get_step
    if has_upstream_image?
      [{
        'get' => upstream_resource_name,
        'trigger' => true,
        'params' => {'skip_download' => true},
        'passed' => [upstream_build_name],
      }]
    else
      []
    end
  end

  def has_upstream_image?
    !! @image.upstream_image
  end

  def upstream_resource_name
    @image.upstream_image + '-resource' if has_upstream_image?
  end

  def upstream_build_name
    'build-' + @image.upstream_image if has_upstream_image?
  end

  def s3_gets
    @image.s3_dependencies.map{|dep|
      resource = @job_resources.get_name(dep)
      {'get' => resource}
    }
  end

  def build_image_step
    [{
      'put' => @job_resources.untested_resource_name,
      'params' => remove_nil_values({
        'build' => '.',
        'dockerfile' => @image.dockerfile_path,
      })
    }]
  end

  def test_image_step
    [{
     'task' => 'image-testing',
     'config' => {
       'platform' => 'linux',
       'image_resource' => @job_resources.untested_image_resource.tap { |hs| hs.delete('name') },
       'inputs' => [{'name' => 'toolsmiths-images'}],
       'run' => {
         'path' => 'toolsmiths-images/' + @image.test_script_path
       }
     }
    }]
  end

  def push_image_step
    [{
      'put' => @job_resources.final_resource_name,
      'params' => {
        'pull_repository' => @image.repository,
        'pull_tag' => @image.untested_tag,
      }
    }]
  end
end

class JobResources

  def initialize(image, all_dependency_names)
    @image = image
    @all_dependency_names = all_dependency_names
  end

  def get_name(dep)
    if @all_dependency_names.count(dep.name) > 1
      "#{@image.name}-#{dep.name}-resource"
    else
      dep.name + '-resource'
    end
  end

  def final_resource_name
    @image.name + '-resource'
  end

  def untested_resource_name
    @image.name + '-untested-resource'
  end

  def s3_resources
    @image.s3_dependencies.map{|dep|
      {
        'name' => get_name(dep),
        'type' => 's3',
        'source' => remove_nil_values({
          'access_key_id' => '{{aws-access-key-id}}',
          'secret_access_key' => '{{aws-secret-access-key}}',
          'bucket' => dep.bucket,
          'region_name' => dep.region_name,
          'versioned_file' => dep.versioned_file,
          'regexp' => dep.regexp,
        })
      }
    }
  end

  def untested_image_resource
    {
      'name' => untested_resource_name,
      'type' => 'docker-image',
      'source' => remove_nil_values({
        'username' => '{{docker-username}}',
        'password' => '{{docker-password}}',
        'repository' => @image.repository,
        'tag' => @image.untested_tag
      })
    }
  end

  def final_image_resource
    {
      'name' => final_resource_name,
      'type' => 'docker-image',
      'source' => remove_nil_values({
        'username' => '{{docker-username}}',
        'password' => '{{docker-password}}',
        'repository' => @image.repository,
        'tag' => @image.tag
      })
    }
  end

  def self.toolsmiths_git_resource
    {
      'name' => 'toolsmiths-images',
      'type' => 'git',
      'source' => {
        'uri' => 'git@github.com:Pivotal-DataFabric/toolsmiths-images.git',
        'branch' => 'master',
        'private_key' => '{{toolsmiths-images-repo-key}}',
      }
    }
  end
end

class DockerImage

  attr_reader :dockerfile_path, :test_script_path

  def initialize(desc, dockerfile_path, test_script_path)
    @desc = desc
    @dockerfile_path = dockerfile_path
    @test_script_path = test_script_path
  end

  def name
    @desc['name']
  end

  def repository
    @desc['repository']
  end

  def tag
    @desc['tag']
  end

  def upstream_image
    @desc['upstream_image']
  end

  def untested_tag
    tag ? tag + '-untested' : 'untested'
  end

  def dependencies
    (@desc['dependencies'] || {}).map{|name, dep| Dependency.new name, dep}
  end

  def s3_dependencies
    dependencies.select(&:is_s3_dependency?)
  end

end

class Dependency

  attr_reader :name

  def initialize(name, dependency)
    @name = name
    @dependency = dependency
  end

  def is_s3_dependency?
    @dependency['type'] == 's3'
  end

  def s3_url
    "s3://#{bucket}/#{normalized_uri}"
  end

  def uri_basename
    File.basename(normalized_uri)
  end

  def resource_name
    @name + '-resource'
  end

  def bucket
    @dependency['bucket']
  end

  def region_name
    @dependency['region_name']
  end

  def versioned_file
    @dependency['versioned_file']
  end

  def regexp
    @dependency['regexp']
  end

  def md5
    str = bucket || ''
    str += regexp|| ''
    str += versioned_file || ''
    Digest::MD5.hexdigest str
  end

private

  def normalized_uri
    remove_version_capturing_regexp(@dependency['regexp']) || @dependency['versioned_file']
  end

  def remove_version_capturing_regexp(path)
    path.gsub(/[)(]/, '') if path
  end
end

def remove_nil_values(hash)
  hash.reject{|k,v| v.nil?}
end
