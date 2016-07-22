import Foundation
import Siesta


/// API for getting TeamCity build information.
class XTTeamCityAPI : XTBasicAuthService, XTServiceAPI {
  
  var type: AccountType { return .TeamCity }
  static let rootPath = "/httpAuth/app/rest"
  
  /// Attribute names of a <build> element.
  enum BuildAttribute: String {
    case ID = "id"
    case BuildType = "buildTypeId"
    case BuildNumber = "number"
    case Status = "status"
    case State = "state"
    case Running = "running"
    case Percentage = "percentageComplete"
    case BranchName = "branchName"
    case HRef = "href"
    case WebURL = "webUrl"
  }
  
  enum BuildStatus: String {
    case Unknown = ""
    case Succeded = "SUCCESS"
    case Failed = "FAILURE"
  }
  
  enum BuildState: String {
    case Running = "running"
    case Finished = "finished"
  }
  
  private(set) var buildTypesStatus = XTServices.Status.NotStarted
  
  /// Maps VCS root ID to repository URL.
  var vcsRootMap = [String: String]()
  var vcsBuildTypes = [String: [String]]()
  
  init?(user: String, password: String, baseURL: String?)
  {
    guard let baseURL = baseURL,
      let fullBaseURL = NSURLComponents(string: baseURL)
      else { return nil }
    
    fullBaseURL.path = XTTeamCityAPI.rootPath
    
    super.init(user: user, password: password, baseURL: fullBaseURL.string,
               authenticationPath: "/")
    
    configure(description: "xml") {
      $0.config.pipeline[.parsing].add(XMLResponseTransformer(),
                                       contentTypes: [ "*/xml" ])
    }
  }
  
  /// Status of the most recent build of the given branch from any project
  /// and build type.
  func buildStatus(branch: String, buildType: String) -> Resource
  {
    // Look up:
    // - builds?locator=running:any,
    //    buildType:\(buildType),branch:\(branch)
    // - Returns a list of <build href=".."/>, retrieve those
    return resource("builds/running:any,branch:\(branch),buildType:\(buildType)")
  }
  
  // Applies the given closure to the build statuses for the given branch and
  // build type.
  func enumerateBuildStatus(branch: String, builtType: String,
                            processor: ([String: String]) -> Void)
  {
    let statusResource = buildStatus(branch, buildType: builtType)
    
    statusResource.useData(self) { (data) in
      guard let xml = data.content as? NSXMLDocument,
        let builds = xml.children?.first?.children
        else {
          NSLog("Couldn't process build statuses: \(data.content)")
          return
      }
      
      for build in builds {
        guard let buildElement = build as? NSXMLElement
          else { continue }
        
        processor(buildElement.attributesDict())
      }
    }
  }
  
  var vcsRoots: Resource
  { return resource("vcs-roots") }
  
  var projects: Resource
  { return resource("projects") }
  
  var buildTypes: Resource
  { return resource("buildTypes") }
  
  /// A resource for the repo URL of a VCS root. This will be just the URL,
  /// not wrapped in XML.
  func vcsRootURL(vcsRoodID: String) -> Resource
  {
    return resource("vcs-roots/id:\(vcsRoodID)/properties/url")
  }
  
  override func didAuthenticate()
  {
    // - Get VCS roots, build repo URL -> vcs-root id map.
    vcsRoots.useData(self) { (data) in
      guard let xml = data.content as? NSXMLDocument
        else {
          NSLog("Couldn't parse vcs-roots xml")
          self.buildTypesStatus = .Failed(nil)  // TODO: ParseError type
          return
      }
      self.parseVCSRoots(xml)
    }
  }
}

// MARK: VCS

extension XTTeamCityAPI {
  
  /// Returns all the build types that use the given remote.
  func buildTypes(forRemote remoteURL: NSString) -> [String]
  {
    var result = [String]()
    
    for (buildType, urls) in vcsBuildTypes {
      if !urls.filter({ $0 == remoteURL }).isEmpty {
        result.append(buildType)
      }
    }
    return result
  }
  
  private func parseVCSRoots(xml: NSXMLDocument)
  {
    guard let vcsRoots = xml.children?.first?.children
      else {
        NSLog("Couldn't parse vcs-roots")
        self.buildTypesStatus = .Failed(nil)
        return
    }
    
    var waitingRootCount = vcsRoots.count
    
    vcsRootMap.removeAll()
    for vcsRoot in vcsRoots {
      guard let element = vcsRoot as? NSXMLElement,
        let rootID = element.attributeForName("id")?.stringValue
        else {
          NSLog("Couldn't parse vcs-roots")
          self.buildTypesStatus = .Failed(nil)
          return
      }
      
      let repoResource = self.vcsRootURL(rootID)
      
      repoResource.useData(self, closure: { (data) in
        if let repoURL = data.content as? String {
          self.vcsRootMap[rootID] = repoURL
        }
        waitingRootCount -= 1
        if (waitingRootCount == 0) {
          self.getBuildTypes()
        }
      })
    }
  }
  
  private func getBuildTypes()
  {
    buildTypes.useData(self) { (data) in
      guard let xml = data.content as? NSXMLDocument
        else {
          NSLog("Couldn't parse build types xml")
          self.buildTypesStatus = .Failed(nil)
          return
      }
      self.parseBuildTypes(xml)
    }
  }
  
  private func parseBuildTypes(xml: NSXMLDocument)
  {
    guard let buildTypesList = xml.rootElement()?.children
      else {
        NSLog("Couldn't parse build types")
        self.buildTypesStatus = .Failed(nil)
        return
    }
    
    var waitingTypeCount = buildTypesList.count
    
    for type in buildTypesList {
      guard let element = type as? NSXMLElement,
        let href = element.attributeForName("href")?.stringValue
        else {
          NSLog("Couldn't parse build type: \(type)")
          self.buildTypesStatus = .Failed(nil)
          return
      }
      
      let relativePath = href.stringByRemovingPrefix(XTTeamCityAPI.rootPath)
      
      resource(relativePath).useData(self, closure: { (data) in
        waitingTypeCount -= 1
        defer {
          if waitingTypeCount == 0 {
            self.buildTypesStatus = .Done
          }
        }
        
        guard let xml = data.content as? NSXMLDocument
          else {
            NSLog("Couldn't parse build type xml: \(data.content)")
            self.buildTypesStatus = .Failed(nil)
            return
        }
        
        self.parseBuildType(xml)
      })
    }
  }
  
  private func parseBuildType(xml: NSXMLDocument)
  {
    guard let buildType = xml.children?.first as? NSXMLElement,
      let rootEntries = buildType.elementsForName("vcs-root-entries").first
      else {
        NSLog("Couldn't find root entries: \(xml)")
        self.buildTypesStatus = .Failed(nil)
        return
    }
    guard let buildTypeID = buildType.attributeForName("id")?.stringValue
      else {
        NSLog("No ID for build type: \(xml)")
        return
    }
    guard let entriesChildren = rootEntries.children
      else { return }  // Empty list is not an error
    
    for entry in entriesChildren {
      guard let entryElement = entry as? NSXMLElement,
        let vcsID = entryElement.attributeForName("id")?.stringValue
        else { continue }
      guard let vcsURL = vcsRootMap[vcsID]
        else {
          NSLog("No match for VCS ID \(vcsID)")
          continue
      }
      
      if var buildTypeURLs = vcsBuildTypes[buildTypeID] {
        // Modify and put it back because Array is a value type
        buildTypeURLs.append(vcsURL)
        vcsBuildTypes[buildTypeID] = buildTypeURLs
      }
      else {
        vcsBuildTypes[buildTypeID] = [vcsURL]
      }
    }
  }
}