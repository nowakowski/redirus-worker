require 'spec_helper'

describe Redirus::Worker::NginxConfigGenerator, 'nginx configuration generation' do

  let(:single_worker) { ['10.100.10.2:80'] }
  let(:two_workers) { ['10.100.10.3:80', '10.100.10.4:80'] }

  context 'when no proxy defined' do
    let(:result) { generate([], []) }

    it 'returns empty configuration for http and https' do
      expect(result[:http]).to conf_be_empty
      expect(result[:https]).to conf_be_empty
    end
  end

  context 'when http proxy' do
    let(:result) { generate([
        {'path' => 'path', 'workers' => single_worker, 'type' => 'http'},
        {'path' => '/proxy/with/two/workers', 'workers' => two_workers, 'type' => 'http'},
        {'path' => 'with space', 'workers' => single_worker, 'type' => 'http'},
      ], []) }

    it 'generates empty config for https' do
      expect(result[:https]).to conf_be_empty
    end

    it 'generates http proxy configuration' do
      expect(result[:http]).to have_config('/path/', 'http.path')
      expect(result[:http]).to have_upstream_config('http.path', single_worker)
    end

    it 'generates proxy configuration with complex path' do
      expect(result[:http]).to have_config('/proxy/with/two/workers/', 'http.proxy.with.two.workers')
    end

    it 'generates http proxy upstream with 2 workers' do
      expect(result[:http]).to have_upstream_config('http.proxy.with.two.workers', two_workers)
    end
  end

  context 'when https proxy' do
    let(:result) { generate([{'path' => '/my/path', 'workers' => single_worker, 'type' => 'https'}], []) }

    it 'generates empty config for http' do
      expect(result[:http]).to conf_be_empty
    end

    it 'generates https proxy configuration' do
      expect(result[:https]).to have_config('/my/path/', 'https.my.path')
      expect(result[:https]).to have_upstream_config('https.my.path', single_worker)
    end
  end

  describe 'properties' do
    let(:path) { '/my/path/' }

    describe 'global' do
      let(:result) { generate([{'path' => path, 'workers' => single_worker, 'type' => 'http'}], properties) }

      context 'which are static' do
        let(:properties) { ['proxy_send_timeout 600', 'my fancy property'] }

        it 'generates additional proxy conf lines with properties' do
          expect(result[:http]).to have_property(path, properties[0])
          expect(result[:http]).to have_property(path, properties[1])
        end
      end

      context 'which are dynamic' do
        let(:properties) { ['proxy_set_header X-Path-Prefix "{{path}}"'] }

        it 'generates additional proxy conf lines with properties' do
          expect(result[:http]).to have_property(path, 'proxy_set_header X-Path-Prefix "/my/path/"')
        end
      end
    end

    describe 'local' do
      let(:result) { generate([{'path' => path, 'workers' => single_worker, 'type' => 'http', 'properties' => local_props}], []) }

      context 'which are static' do
        let(:local_props) { ['prop1', 'prop2'] }

        it 'generates local properties lines' do
          expect(result[:http]).to have_property(path, local_props[0])
          expect(result[:http]).to have_property(path, local_props[1])
        end
      end

      context 'which are dynamic' do
        let(:local_props) { ['proxy_set_header X-Path-Prefix "{{path}}"'] }

        it 'generates local properties lines' do
          expect(result[:http]).to have_property(path, 'proxy_set_header X-Path-Prefix "/my/path/"')
        end
      end
    end
  end

  def generate(proxies, properties)
    Redirus::Worker::NginxConfigGenerator.new(proxies, properties).generate
  end
end