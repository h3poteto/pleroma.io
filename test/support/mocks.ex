# Pleroma: A lightweight social networking server
# Copyright © 2017-2022 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

Mox.defmock(Pleroma.CachexMock, for: Pleroma.Caching)

Mox.defmock(Pleroma.Web.ActivityPub.ObjectValidatorMock,
  for: Pleroma.Web.ActivityPub.ObjectValidator.Validating
)

Mox.defmock(Pleroma.Web.ActivityPub.MRFMock,
  for: Pleroma.Web.ActivityPub.MRF.PipelineFiltering
)

Mox.defmock(Pleroma.Web.ActivityPub.ActivityPubMock,
  for: [
    Pleroma.Web.ActivityPub.ActivityPub.Persisting,
    Pleroma.Web.ActivityPub.ActivityPub.Streaming
  ]
)

Mox.defmock(Pleroma.Web.ActivityPub.SideEffectsMock,
  for: Pleroma.Web.ActivityPub.SideEffects.Handling
)

Mox.defmock(Pleroma.Web.FederatorMock, for: Pleroma.Web.Federator.Publishing)

Mox.defmock(Pleroma.ConfigMock, for: Pleroma.Config.Getting)
Mox.defmock(Pleroma.UnstubbedConfigMock, for: Pleroma.Config.Getting)
Mox.defmock(Pleroma.StaticStubbedConfigMock, for: Pleroma.Config.Getting)
Mox.defmock(Pleroma.StubbedHTTPSignaturesMock, for: Pleroma.HTTPSignaturesAPI)

Mox.defmock(Pleroma.LoggerMock, for: Pleroma.Logging)

Mox.defmock(Pleroma.Uploaders.S3.ExAwsMock, for: Pleroma.Uploaders.S3.ExAwsAPI)

Mox.defmock(Pleroma.DateTimeMock, for: Pleroma.DateTime)
Mox.defmock(Pleroma.MogrifyMock, for: Pleroma.MogrifyBehaviour)
