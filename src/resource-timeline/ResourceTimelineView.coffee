
class ResourceTimelineView extends TimelineView

	ResourceViewMixin.mixOver(this)

	# configuration for View monkeypatch
	canHandleSpecificResources: true

	# configuration for DateComponent monkeypatch
	isResourceFootprintsEnabled: true

	# renders non-resource bg events only
	eventRendererClass: ResourceTimelineEventRenderer

	# time area
	timeBodyTbodyEl: null

	# spreadsheet area
	spreadsheet: null

	# divider
	dividerEls: null
	dividerWidth: null

	# resource rendering options
	superHeaderText: null
	isVGrouping: null
	isHGrouping: null
	groupSpecs: null
	colSpecs: null
	orderSpecs: null

	# resource rows
	tbodyHash: null # used by RowParent
	rowHierarchy: null
	resourceRowHash: null
	nestingCnt: 0
	isNesting: null
	eventRows: null
	shownEventRows: null
	resourceScrollJoiner: null
	rowsNeedingHeightSync: null

	# positioning
	rowCoordCache: null


	constructor: ->
		super
		@initResourceView()
		@processResourceOptions()
		@spreadsheet = new Spreadsheet(this)
		@rowHierarchy = new RowParent(this)
		@rowHierarchy.isExpanded = true # hack to always show, regardless of resourcesInitiallyExpanded
		@resourceRowHash = {}


	# Resource Options
	# ------------------------------------------------------------------------------------------------------------------


	processResourceOptions: ->
		allColSpecs = @opt('resourceColumns') or []
		labelText = @opt('resourceLabelText') # TODO: view.override
		defaultLabelText = 'Resources' # TODO: view.defaults
		superHeaderText = null

		if not allColSpecs.length
			allColSpecs.push
				labelText: labelText or defaultLabelText
				text: @getResourceTextFunc()
		else
			superHeaderText = labelText

		plainColSpecs = []
		groupColSpecs = []
		groupSpecs = []
		isVGrouping = false
		isHGrouping = false

		for colSpec in allColSpecs
			if colSpec.group
				groupColSpecs.push(colSpec)
			else
				plainColSpecs.push(colSpec)

		plainColSpecs[0].isMain = true

		if groupColSpecs.length
			groupSpecs = groupColSpecs
			isVGrouping = true
		else
			hGroupField = @opt('resourceGroupField')
			if hGroupField
				isHGrouping = true
				groupSpecs.push
					field: hGroupField
					text: @opt('resourceGroupText')
					render: @opt('resourceGroupRender')

		allOrderSpecs = parseFieldSpecs(@opt('resourceOrder'))
		plainOrderSpecs = []

		for orderSpec in allOrderSpecs
			isGroup = false
			for groupSpec in groupSpecs
				if groupSpec.field == orderSpec.field
					groupSpec.order = orderSpec.order # -1, 0, 1
					isGroup = true
					break
			if not isGroup
				plainOrderSpecs.push(orderSpec)

		@superHeaderText = superHeaderText
		@isVGrouping = isVGrouping
		@isHGrouping = isHGrouping
		@groupSpecs = groupSpecs
		@colSpecs = groupColSpecs.concat(plainColSpecs)
		@orderSpecs = plainOrderSpecs


	# Skeleton Rendering
	# ------------------------------------------------------------------------------------------------------------------


	renderSkeleton: ->
		super

		theme = @calendar.theme

		@spreadsheet.el = @el.find('tbody .fc-resource-area')
		@spreadsheet.headEl = @el.find('thead .fc-resource-area')
		@spreadsheet.renderSkeleton()
		# ^ is not a Grid/DateComponent

		# only non-resource grid needs this, so kill it
		# TODO: look into better solution
		@segContainerEl.remove()
		@segContainerEl = null

		timeBodyContainerEl = $('
			<div class="fc-rows">
				<table class="' + theme.getClass('tableGrid') + '">
					<tbody/>
				</table>
			</div>
		').appendTo(@timeBodyScroller.canvas.contentEl)
		@timeBodyTbodyEl = timeBodyContainerEl.find('tbody')

		@tbodyHash = { # needed for rows to render
			spreadsheet: @spreadsheet.tbodyEl
			event: @timeBodyTbodyEl
		}

		@resourceScrollJoiner = new ScrollJoiner('vertical', [
			@spreadsheet.bodyScroller
			@timeBodyScroller
		])

		@initDividerMoving()


	renderSkeletonHtml: ->
		theme = @calendar.theme

		'<table class="' + theme.getClass('tableGrid') + '">
			<thead class="fc-head">
				<tr>
					<td class="fc-resource-area ' + theme.getClass('widgetHeader') + '"></td>
					<td class="fc-divider fc-col-resizer ' + theme.getClass('widgetHeader') + '"></td>
					<td class="fc-time-area ' + theme.getClass('widgetHeader') + '"></td>
				</tr>
			</thead>
			<tbody class="fc-body">
				<tr>
					<td class="fc-resource-area ' + theme.getClass('widgetContent') + '"></td>
					<td class="fc-divider fc-col-resizer ' + theme.getClass('widgetHeader') + '"></td>
					<td class="fc-time-area ' + theme.getClass('widgetContent') + '"></td>
				</tr>
			</tbody>
		</table>'


	# Divider Moving
	# ------------------------------------------------------------------------------------------------------------------


	initDividerMoving: ->
		@dividerEls = @el.find('.fc-divider')

		@dividerWidth = @opt('resourceAreaWidth') ? @spreadsheet.tableWidth # tableWidth available after spreadsheet.renderSkeleton
		if @dividerWidth?
			@positionDivider(@dividerWidth)

		@dividerEls.on 'mousedown', (ev) =>
			@dividerMousedown(ev)


	dividerMousedown: (ev) ->
		isRTL = @opt('isRTL')
		minWidth = 30
		maxWidth = @el.width() - 30
		origWidth = @getNaturalDividerWidth()

		dragListener = new DragListener

			dragStart: =>
				@dividerEls.addClass('fc-active')

			drag: (dx, dy) =>
				if isRTL
					width = origWidth - dx
				else
					width = origWidth + dx

				width = Math.max(width, minWidth)
				width = Math.min(width, maxWidth)

				@dividerWidth = width
				@positionDivider(width)
				@calendar.updateViewSize() # if in render queue, will wait until end

			dragEnd: =>
				@dividerEls.removeClass('fc-active')

		dragListener.startInteraction(ev)


	getNaturalDividerWidth: ->
		@el.find('.fc-resource-area').width() # TODO: don't we have this cached?


	positionDivider: (w) ->
		@el.find('.fc-resource-area').css('width', w) # TODO: don't we have this cached?


	# Sizing
	# ------------------------------------------------------------------------------------------------------------------


	updateSize: (totalHeight, isAuto, isResize) ->

		if @rowsNeedingHeightSync
			@syncRowHeights(@rowsNeedingHeightSync)
			@rowsNeedingHeightSync = null
		else # a resize or an event rerender
			@syncRowHeights() # sync all

		headHeight = @syncHeadHeights()

		if isAuto
			bodyHeight = 'auto'
		else
			bodyHeight = totalHeight - headHeight - @queryMiscHeight()

		@timeBodyScroller.setHeight(bodyHeight)
		@spreadsheet.bodyScroller.setHeight(bodyHeight)
		@spreadsheet.updateSize()

		# do children AFTER because of ScrollFollowerSprite abs position issues
		super

		# do once spreadsheet area and event slat area have correct height, for gutters
		@resourceScrollJoiner.update()


	queryMiscHeight: ->
		@el.outerHeight() -
			Math.max(@spreadsheet.headScroller.el.outerHeight(), @timeHeadScroller.el.outerHeight()) -
			Math.max(@spreadsheet.bodyScroller.el.outerHeight(), @timeBodyScroller.el.outerHeight())


	syncHeadHeights: ->
		@spreadsheet.headHeight('auto')
		@headHeight('auto')

		headHeight = Math.max(@spreadsheet.headHeight(), @headHeight())

		@spreadsheet.headHeight(headHeight)
		@headHeight(headHeight)

		headHeight


	# Scrolling
	# ------------------------------------------------------------------------------------------------------------------
	# this is useful for scrolling prev/next dates while resource is scrolled down


	queryResourceScroll: ->
		scroll = {}

		scrollerTop = @timeBodyScroller.scrollEl.offset().top # TODO: use getClientRect

		for rowObj in @getVisibleRows()
			if rowObj.resource
				el = rowObj.getTr('event')
				elBottom = el.offset().top + el.outerHeight()

				if elBottom > scrollerTop
					scroll.resourceId = rowObj.resource.id
					scroll.bottom = elBottom - scrollerTop
					break

		# TODO: what about left scroll state for spreadsheet area?
		scroll


	applyResourceScroll: (scroll) ->
		if scroll.resourceId
			row = @getResourceRow(scroll.resourceId)
			if row
				el = row.getTr('event')
				if el
					innerTop = @timeBodyScroller.canvas.el.offset().top # TODO: use -scrollHeight or something
					elBottom = el.offset().top + el.outerHeight()
					scrollTop = elBottom - scroll.bottom - innerTop
					@timeBodyScroller.setScrollTop(scrollTop)
					@spreadsheet.bodyScroller.setScrollTop(scrollTop)


	scrollToResource: (resource) ->
		row = @getResourceRow(resource.id)
		if row
			el = row.getTr('event')
			if el
				innerTop = @timeBodyScroller.canvas.el.offset().top # TODO: use -scrollHeight or something
				scrollTop = el.offset().top - innerTop
				@timeBodyScroller.setScrollTop(scrollTop)
				@spreadsheet.bodyScroller.setScrollTop(scrollTop)


	# Hit System
	# ------------------------------------------------------------------------------------------------------------------


	prepareHits: ->
		super

		@eventRows = @getEventRows()
		@shownEventRows = (row for row in @eventRows when row.get('isInDom'))

		trArray =
			for row in @shownEventRows
				row.getTr('event')[0]

		@rowCoordCache = new CoordCache
			els: trArray
			isVertical: true
		@rowCoordCache.build()


	releaseHits: ->
		super
		@eventRows = null
		@shownEventRows = null
		@rowCoordCache.clear()


	queryHit: (leftOffset, topOffset) ->
		simpleHit = super
		if simpleHit
			rowIndex = @rowCoordCache.getVerticalIndex(topOffset)
			if rowIndex?
				{
					resourceId: @shownEventRows[rowIndex].resource.id
					snap: simpleHit.snap
					component: this # need this unfortunately :(
					left: simpleHit.left
					right: simpleHit.right
					top: @rowCoordCache.getTopOffset(rowIndex)
					bottom: @rowCoordCache.getBottomOffset(rowIndex)
				}


	getHitFootprint: (hit) ->
		componentFootprint = super
		new ResourceComponentFootprint(
			componentFootprint.unzonedRange
			componentFootprint.isAllDay
			hit.resourceId
		)


	getHitEl: (hit) ->
		@getSnapEl(hit.snap)


	# Resource Data
	# ------------------------------------------------------------------------------------------------------------------


	renderResources: (resources) ->
		for resource in resources
			@renderResource(resource)


	unrenderResources: ->
		@rowHierarchy.removeElement()
		@rowHierarchy.removeChildren()

		for id, row in @resourceRowHash
			@removeChild(row) # for DateComponent!

		@resourceRowHash = {}


	renderResource: (resource) ->
		@insertResource(resource)


	unrenderResource: (resource) ->
		@removeResource(resource)


	# Event Rendering
	# ------------------------------------------------------------------------------------------------------------------


	executeEventRender: (eventsPayload) ->
		payloadsByResourceId = {}
		genericPayload = {}

		for eventDefId, eventInstanceGroup of eventsPayload
			eventDef = eventInstanceGroup.getEventDef()
			resourceIds = eventDef.getResourceIds()

			if resourceIds.length
				for resourceId in resourceIds
					(payloadsByResourceId[resourceId] ?= {})[eventDefId] = eventInstanceGroup
			# only render bg segs that have no resources
			else if eventDef.hasBgRendering()
				genericPayload[eventDefId] = eventInstanceGroup

		@eventRenderer.render(genericPayload)

		for resourceId, resourceEventsPayload of payloadsByResourceId
			row = @getResourceRow(resourceId)

			if row
				#Adds all the resources that are currently being worked on to watchers
				@_watchers.resourcesServiced = payloadsByResourceId
				row.executeEventRender(resourceEventsPayload)

		return


	# Business Hours Rendering
	# ------------------------------------------------------------------------------------------------------------------

	indiBizCnt: 0 # number of resources with "independent" business hour definition
	isIndiBizRendered: false # are resources displaying business hours individually?
	isGenericBizRendered: false # is generic business hours rendered? (means all resources have same)
	genericBiz: null # generic (non-resource-specific) business hour generator


	renderBusinessHours: (businessHourGenerator) ->
		@genericBiz = businessHourGenerator # save for later
		@isIndiBizRendered = false
		@isGenericBizRendered = false

		if @indiBizCnt
			@isIndiBizRendered = true
			for row in @getEventRows()
				row.renderBusinessHours(row.resource.businessHourGenerator or businessHourGenerator)
		else
			@isGenericBizRendered = true
			@businessHourRenderer.render(businessHourGenerator)


	updateIndiBiz: ->
		if (@indiBizCnt and @isGenericBizRendered) or (not @indiBizCnt and @isIndiBizRendered)
			@unrenderBusinessHours()
			@renderBusinessHours(@genericBiz)


	# Row Management
	# ------------------------------------------------------------------------------------------------------------------


	# creates a row for the given resource and inserts it into the hierarchy.
	# if `parentResourceRow` is given, inserts it as a direct child
	# does not render
	insertResource: (resource, parentResourceRow) ->
		noExplicitParent = !parentResourceRow
		row = new ResourceRow(this, resource)
		shouldRender = false

		if not parentResourceRow
			if resource.parent
				parentResourceRow = @getResourceRow(resource.parent.id)
			else if resource.parentId
				parentResourceRow = @getResourceRow(resource.parentId)

		if parentResourceRow
			@insertRowAsChild(row, parentResourceRow)
		else
			@insertRow(row)

		@addChild(row) # for DateComponent!
		@resourceRowHash[resource.id] = row

		if resource.businessHourGenerator
			@indiBizCnt++

			# hack to get dynamically-added resources with custom business hours to render
			if @isIndiBizRendered
				row.businessHourGenerator = resource.businessHourGenerator

			@updateIndiBiz()

		for childResource in resource.children
			@insertResource(childResource, row)

		if noExplicitParent and computeIsChildrenVisible(row.parent)
			row.renderSkeleton()

		row


	# does not unrender
	removeResource: (resource) ->
		row = @resourceRowHash[resource.id]

		if row
			delete @resourceRowHash[resource.id]

			@removeChild(row) # for DateComponent!

			row.removeFromParentAndDom()

			if resource.businessHourGenerator
				@indiBizCnt--
				@updateIndiBiz()

		row


	# inserts the given row into the hierarchy.
	# `parent` can be any tree root of the hierarchy.
	# `orderSpecs` will recursively create groups within the root before inserting the row.
	insertRow: (row, parent=@rowHierarchy, groupSpecs=@groupSpecs) ->
		if groupSpecs.length
			group = @ensureResourceGroup(row, parent, groupSpecs[0])

			if group instanceof HRowGroup
				@insertRowAsChild(row, group) # horizontal rows can only be one level deep
			else
				@insertRow(row, group, groupSpecs.slice(1))
		else
			@insertRowAsChild(row, parent)


	# inserts the given row as a direct child of the given parent
	insertRowAsChild: (row, parent) ->
		parent.addChild(row, @computeChildRowPosition(row, parent))


	# computes the position at which the given node should be inserted into the parent's children
	# if no specific position is determined, returns null
	computeChildRowPosition: (child, parent) ->
		if @orderSpecs.length
			for sibling, i in parent.children
				cmp = @compareResources(sibling.resource or {}, child.resource or {})
				if cmp > 0 # went 1 past. insert at i
					return i
		null


	# given two resources, returns a cmp value (-1, 0, 1)
	compareResources: (a, b) ->
		compareByFieldSpecs(a, b, @orderSpecs)


	# given information on how a row should be inserted into one of the parent's child groups,
	# ensure a child group exists, creating it if necessary, and then return it.
	# spec MIGHT NOT HAVE AN ORDER
	ensureResourceGroup: (row, parent, spec) ->
		groupValue = (row.resource or {})[spec.field] # the groupValue of the row
		group = null

		# find an existing group that matches, or determine the position for a new group
		if spec.order
			for testGroup, i in parent.children
				cmp = flexibleCompare(testGroup.groupValue, groupValue) * spec.order
				if cmp == 0 # an exact match with an existing group
					group = testGroup
					break
				else if cmp > 0 # the row's desired group is after testGroup. insert at this position
					break
		else # the groups are unordered
			for testGroup, i in parent.children
				if testGroup.groupValue == groupValue
					group = testGroup
					break
			# `i` will be at the end if group was not found

		# create a new group
		if not group
			if @isVGrouping
				group = new VRowGroup(this, spec, groupValue)
			else
				group = new HRowGroup(this, spec, groupValue)

			parent.addChild(group, i)
			group.renderSkeleton() # always immediately render groups

		group


	# Row Rendering
	# ------------------------------------------------------------------------------------------------------------------


	descendantAdded: (row) ->
		wasNesting = @isNesting
		isNesting = Boolean(
			@nestingCnt += if row.depth then 1 else 0
		)

		if wasNesting != isNesting

			@el.toggleClass('fc-nested', isNesting)
				.toggleClass('fc-flat', not isNesting)

			@isNesting = isNesting


	descendantRemoved: (row) ->
		wasNesting = @isNesting
		isNesting = Boolean(
			@nestingCnt -= if row.depth then 1 else 0
		)

		if wasNesting != isNesting

			@el.toggleClass('fc-nested', isNesting)
				.toggleClass('fc-flat', not isNesting)

			@isNesting = isNesting


	descendantShown: (row) ->
		(@rowsNeedingHeightSync or= []).push(row)
		return


	descendantHidden: (row) ->
		@rowsNeedingHeightSync or= [] # signals to updateSize that specific rows hidden
		return


	# visibleRows is flat. does not do recursive
	syncRowHeights: (visibleRows, safe=false) ->

		visibleRows ?= @getVisibleRows()

		for row in visibleRows
			row.setTrInnerHeight('')

		innerHeights = for row in visibleRows
			h = row.getMaxTrInnerHeight()
			if safe
				h += h % 2 # FF and zoom only like even numbers for alignment
			h

		for row, i in visibleRows
			row.setTrInnerHeight(innerHeights[i])

		if not safe
			h1 = @spreadsheet.tbodyEl.height()
			h2 = @timeBodyTbodyEl.height()
			if Math.abs(h1 - h2) > 1
				@syncRowHeights(visibleRows, true)


	# Row Querying
	# ------------------------------------------------------------------------------------------------------------------


	getVisibleRows: ->
		row for row in @rowHierarchy.getRows() when row.get('isInDom')


	getEventRows: ->
		row for row in @rowHierarchy.getRows() when row instanceof EventRow


	getResourceRow: (resourceId) ->
		@resourceRowHash[resourceId]


	# Selection
	# ------------------------------------------------------------------------------------------------------------------


	renderSelectionFootprint: (componentFootprint) ->
		if componentFootprint.resourceId
			rowObj = @getResourceRow(componentFootprint.resourceId)
			if rowObj
				rowObj.renderSelectionFootprint(componentFootprint)
		else
			super


	# Event Resizing (route to rows)
	# ------------------------------------------------------------------------------------------------------------------


	renderEventResize: (eventFootprints, seg, isTouch) ->
		map = groupEventFootprintsByResourceId(eventFootprints)

		for resourceId, resourceEventFootprints of map
			rowObj = @getResourceRow(resourceId)

			# render helpers
			rowObj.helperRenderer.renderEventDraggingFootprints(resourceEventFootprints, seg, isTouch)

			# render highlight
			for eventFootprint in resourceEventFootprints
				rowObj.renderHighlight(eventFootprint.componentFootprint)


	unrenderEventResize: ->
		for rowObj in @getEventRows()
			rowObj.helperRenderer.unrender()
			rowObj.unrenderHighlight()


	# DnD (route to rows)
	# ------------------------------------------------------------------------------------------------------------------


	renderDrag: (eventFootprints, seg, isTouch) ->
		map = groupEventFootprintsByResourceId(eventFootprints)

		if seg
			# draw helper
			for resourceId, resourceEventFootprints of map
				rowObj = @getResourceRow(resourceId)
				rowObj.helperRenderer.renderEventDraggingFootprints(resourceEventFootprints, seg, isTouch)

			true # signal helper rendered
		else
			# draw highlight
			for resourceId, resourceEventFootprints of map
				for eventFootprint in resourceEventFootprints
					rowObj = @getResourceRow(resourceId)
					rowObj.renderHighlight(eventFootprint.componentFootprint)

			false # signal helper not rendered


	unrenderDrag: ->
		for rowObj in @getEventRows()
			rowObj.helperRenderer.unrender()
			rowObj.unrenderHighlight()


# Utils
# ------------------------------------------------------------------------------------------------------------------


groupEventFootprintsByResourceId = (eventFootprints) ->
	map = {}

	for eventFootprint in eventFootprints
		(map[eventFootprint.componentFootprint.resourceId] or= [])
			.push(eventFootprint)

	map


###
if `current` is null, returns true
###
computeIsChildrenVisible = (current) ->
	while current
		if not current.isExpanded
			return false
		current = current.parent
	return true


FC.ResourceTimelineView = ResourceTimelineView
