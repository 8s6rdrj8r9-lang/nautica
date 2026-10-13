import Foundation
import CryptoKit
// Dependency adapter: these two helpers are verbatim from frozen GraphStore, lines 36-41.
// GRDB persistence is not exercised by this harness; the package parser itself is unmodified.
enum GraphStore {
 static func encode<T: Encodable>(_ value: T) throws -> Data { let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]; return try encoder.encode(value) }
 static func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
}
@main struct UtilitiesProbe {
 static func main() async throws {
  let fm=FileManager.default,root=URL(fileURLWithPath:"/private/tmp/nautica-audit-utility-"+UUID().uuidString,isDirectory:true)
  try fm.createDirectory(at:root,withIntermediateDirectories:true)
  var result:[String:Any]=[:]
  let pkg=try PAFPackageLoader.load(archive:URL(fileURLWithPath:"/Users/arthur/Library/Mobile Documents/com~apple~CloudDocs/PAF-v0.1-Auditor-Kit.zip"),manifestURL:URL(fileURLWithPath:"/Users/arthur/Library/Mobile Documents/com~apple~CloudDocs/paf-package.json"))
  result["supplied_paf_package"]=["ready":pkg.0.ready,"blockers":pkg.0.blockers,"notes":pkg.0.integrityNotes,"file_count":pkg.0.files.count,"original_archive_hash":pkg.0.archiveHash]
  let mp3=root.appendingPathComponent("metadata.mp3")
  let frame:[UInt8]=Array("TPE1".utf8)+[0,0,0,8,0,0,0]+Array("ARTISTX".utf8)
  let header:[UInt8]=[0x49,0x44,0x33,3,0,0,0,0,0,UInt8(frame.count)]
  let raw=Data("SYNTHETIC AUDIO PAYLOAD".utf8)
  try (Data(header+frame)+raw).write(to:mp3)
  try MetadataEditorService.shared.writeAudioMetadata(at:mp3,title:"NEW TITLE")
  let bytes=try Data(contentsOf:mp3)
  result["mp3_title_edit"]=["old_artist_frame_retained":bytes.range(of:Data("TPE1".utf8)) != nil,"new_title_frame_present":bytes.range(of:Data("TIT2".utf8)) != nil,"audio_payload_retained":bytes.suffix(raw.count)==raw,"fixture":"synthetic ID3v2.3 header and artist text frame; no codec playback claim"]
  let dupdir=root.appendingPathComponent("duplicates",isDirectory:true); try fm.createDirectory(at:dupdir,withIntermediateDirectories:true)
  for (n,s) in [("a.txt","abc"),("b.txt","abc"),("c.txt","abd")] {try Data(s.utf8).write(to:dupdir.appendingPathComponent(n))}
  let groups=try await DuplicateFinderService.shared.scan(directory:dupdir)
  result["duplicate_control"]=["groups":groups.count,"counts":groups.map{$0.files.count},"reclaimable":groups.map{$0.reclaimableBytes}]
  result["checksum_abc"]=try await ChecksumService.shared.computeSHA256(url:dupdir.appendingPathComponent("a.txt"))
  result["root"]=root.path
  FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys]))
 }
}
