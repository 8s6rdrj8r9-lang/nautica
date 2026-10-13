import Foundation
@main struct CapacityProbe {
 @MainActor static func main() async throws {
  let root=URL(fileURLWithPath:"/private/tmp/nautica-audit-capacity-"+UUID().uuidString,isDirectory:true),fm=FileManager.default
  try fm.createDirectory(at:root,withIntermediateDirectories:true)
  try PerformanceProfilerService.shared.createSyntheticDirectory(at:root,count:15000)
  var measurements:[[String:Any]]=[]
  for i in 0..<3 {let t=Date();let items=try await FileSystemService.shared.contentsOfDirectory(at:root,includingHidden:false);measurements.append(["run":i+1,"count":items.count,"service_listing_ms":Date().timeIntervalSince(t)*1000])}
  let items=(0..<50000).map {i in FileItem(url:root.appendingPathComponent("sample\(i).txt"),name:"sample\(i).txt",isDirectory:false,size:Int64(i),modificationDate:nil,creationDate:nil,isHidden:false,kind:"text")}
  let t=Date();let sorted=DirectoryContents.sort(items,by:.name,ascending:true);let sortMS=Date().timeIntervalSince(t)*1000
  let model=BatchRenameModel(items:Array(items.prefix(3)));model.formatType = .customPattern;model.sequencePattern="vacation_###.txt"
  let repo=root.appendingPathComponent("git-fixture",isDirectory:true);try fm.createDirectory(at:repo,withIntermediateDirectories:true)
  _=GitService.shared.runGit(["init","-q"],at:repo)
  let filename="file with spaces.txt";try Data("SYNTHETIC".utf8).write(to:repo.appendingPathComponent(filename))
  let gitMap=GitService.shared.statusMap(forDirectory:repo)
  let output:[String:Any]=["root":root.path,"listing":measurements,"sort_50000_ms":sortMS,"sort_count":sorted.count,"measurement_limit":"service enumeration and in-memory sort; no display frame rate, paint, window or Quick Look latency measured","batch_custom_pattern":model.previewItems.map{$0.newName},"git_spaced_filename_mapped":gitMap[filename] != nil,"git_status_keys":Array(gitMap.keys).sorted()]
  FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject:output,options:[.prettyPrinted,.sortedKeys]))
 }
}
